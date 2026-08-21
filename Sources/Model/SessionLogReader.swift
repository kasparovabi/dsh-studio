#if os(macOS)
import Foundation

// dsh refuses to serve a session log whose sequence numbers or frame boundaries
// fail its integrity check, which makes older sessions unreadable even though
// the records themselves parse. The log is the source of truth, so read it
// directly and skip the damaged records instead of losing the whole session.
enum SessionLogReader {
    // The log is a run of concatenated zstd frames, one per commit, and
    // zstdDecompressSync stops after the first. Split on the frame magic and
    // decode each region; a magic that turns out to be compressed data just
    // fails, so widen the region and retry rather than dropping the records.
    private static let script = """
    const z = require('node:zlib'), fs = require('fs');
    const buf = fs.readFileSync(process.argv[1]);
    const MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);
    const offsets = [];
    for (let i = 0; ; ) {
      const at = buf.indexOf(MAGIC, i);
      if (at < 0) break;
      offsets.push(at);
      i = at + 4;
    }
    let text = '';
    for (let k = 0; k < offsets.length; ) {
      let advanced = false;
      for (let j = k + 1; j <= offsets.length; j++) {
        const end = j < offsets.length ? offsets[j] : buf.length;
        try {
          text += z.zstdDecompressSync(buf.subarray(offsets[k], end)).toString('utf8');
          k = j;
          advanced = true;
          break;
        } catch {}
      }
      if (!advanced) k++;
    }
    const out = [];
    for (const line of text.split('\\n')) {
      const s = line.trim();
      if (!s) continue;
      try { out.push(JSON.parse(s)); } catch {}
    }
    process.stdout.write(JSON.stringify(out));
    """

    static func logURL(for sessionId: String) -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh/sessions")
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { return nil }
        for project in projects {
            let candidate = project.appendingPathComponent(sessionId).appendingPathComponent("session.jsonl.zstd")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static func nodeExecutable() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func events(for sessionId: String) -> [[String: Any]] {
        guard let log = logURL(for: sessionId), let node = nodeExecutable() else { return [] }
        let process = Process()
        process.executableURL = node
        process.arguments = ["-e", script, log.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }
        return parsed
    }
}
#endif
