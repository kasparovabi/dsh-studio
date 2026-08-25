#if os(macOS)
import Foundation
import OSLog

enum SessionLogFailure: LocalizedError {
    case noLog
    case noNode
    case nodeTooOld
    case spawnFailed(String)
    case exited(Int32, String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noLog: return "no session log on this machine"
        case .noNode: return "no node binary to read the log with"
        case .nodeTooOld: return "the node on this machine cannot decompress the log (22.15 or newer is needed)"
        case .spawnFailed(let why): return "could not start the log reader: \(why)"
        case .exited(let status, let stderr):
            return stderr.isEmpty ? "the log reader exited \(status)" : "the log reader failed: \(stderr)"
        case .unreadable: return "the log reader returned nothing that parses"
        }
    }
}

// dsh refuses to serve a session log whose sequence numbers or frame boundaries
// fail its integrity check, which makes older sessions unreadable even though
// the records themselves parse. The log is the source of truth, so read it
// directly and skip the damaged records instead of losing the whole session.
enum SessionLogReader {
    private static let log = Logger(subsystem: "com.kasparov.dsh-studio", category: "salvage")

    // The log is a run of concatenated zstd frames, one per commit, and
    // zstdDecompressSync stops after the first. Split on the frame magic and
    // decode each region; a magic that turns out to be compressed data just
    // fails, so widen the region and retry rather than dropping the records.
    //
    // Records come back one per line rather than as one array, and only the
    // trailing window is emitted: a long transcript otherwise exists three times
    // over inside node, as text, as parsed objects and as a re-serialised array,
    // before Swift has seen any of it.
    private static let script = """
    const z = require('node:zlib'), fs = require('fs');
    const limit = Number(process.argv[2] || 4000);
    const buf = fs.readFileSync(process.argv[1]);
    const MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);
    const offsets = [];
    for (let i = 0; ; ) {
      const at = buf.indexOf(MAGIC, i);
      if (at < 0) break;
      offsets.push(at);
      i = at + 4;
    }
    const keep = [];
    let carry = '';
    const take = (line) => {
      const s = line.trim();
      if (!s) return;
      keep.push(s);
      if (keep.length > limit) keep.shift();
    };
    for (let k = 0; k < offsets.length; ) {
      let advanced = false;
      for (let j = k + 1; j <= offsets.length; j++) {
        const end = j < offsets.length ? offsets[j] : buf.length;
        try {
          const chunk = carry + z.zstdDecompressSync(buf.subarray(offsets[k], end)).toString('utf8');
          const lines = chunk.split('\\n');
          carry = lines.pop() ?? '';
          for (const line of lines) take(line);
          k = j;
          advanced = true;
          break;
        } catch {}
      }
      if (!advanced) k++;
    }
    take(carry);
    for (const line of keep) {
      try { JSON.parse(line); } catch { continue; }
      process.stdout.write(line + '\\n');
    }
    """

    static func logURL(for sessionId: String) -> URL? {
        guard SessionID.isSafe(sessionId) else { return nil }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh/sessions").standardizedFileURL
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { return nil }
        for project in projects {
            let candidate = project.appendingPathComponent(sessionId)
                .appendingPathComponent("session.jsonl.zstd").standardizedFileURL
            guard candidate.path.hasPrefix(root.path + "/") else { continue }
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    // zstdDecompressSync arrived in Node 22.15, and these paths hold whatever
    // each machine happens to have installed, so the candidate is asked rather
    // than assumed.
    private static let nodeCandidates = [
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        "/usr/bin/node",
    ]

    private static func nodeExecutable() -> URL? {
        for path in nodeCandidates where FileManager.default.isExecutableFile(atPath: path) {
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: path)
            probe.arguments = ["-e", "process.exit(typeof require('node:zlib').zstdDecompressSync === 'function' ? 0 : 1)"]
            probe.standardOutput = FileHandle.nullDevice
            probe.standardError = FileHandle.nullDevice
            guard (try? probe.run()) != nil else { continue }
            probe.waitUntilExit()
            if probe.terminationStatus == 0 { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    static func events(for sessionId: String, limit: Int = 4000) -> Result<[[String: Any]], SessionLogFailure> {
        guard let log = logURL(for: sessionId) else { return .failure(.noLog) }
        guard let node = nodeExecutable() else {
            let anyNode = nodeCandidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
            return .failure(anyNode ? .nodeTooOld : .noNode)
        }
        let process = Process()
        process.executableURL = node
        process.arguments = ["-e", script, log.path, String(limit)]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return .failure(.spawnFailed(error.localizedDescription))
        }

        // The retry loop can walk a damaged log a long way, and nothing else
        // here would ever stop it.
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            Self.log.error("salvage reader exceeded 60s on \(sessionId, privacy: .public)")
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: watchdog)

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else {
            return .failure(.exited(process.terminationStatus, stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        var parsed: [[String: Any]] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            parsed.append(object)
        }
        return parsed.isEmpty ? .failure(.unreadable) : .success(parsed)
    }
}
#endif
