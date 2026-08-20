import Foundation

// Claude Code writes one JSON object per line into
// ~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl. Those transcripts are
// read-only here: this app drives dsh, so a Claude Code session can be browsed
// but never continued.
enum ClaudeCodeReader {
    static let transcriptCap = 300

    private static let noisePrefixes = [
        "<command-", "<local-command", "<system-reminder", "<task-notification",
        "<scheduled-wakeup", "<background-task", "[Request interrupted", "Caveat:",
    ]

    private static var projectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    private static func text(of content: Any?) -> String {
        if let string = content as? String { return string }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            let value = block["text"] as? String
            return (value?.isEmpty ?? true) ? nil : value
        }.joined(separator: "\n")
    }

    private static func isNoise(_ text: String) -> Bool {
        noisePrefixes.contains { text.hasPrefix($0) }
    }

    // A head read is enough for the list: the working directory and the opening
    // prompt both land in the first lines, and the file's mtime is a cheaper
    // last-activity than parsing the tail of a transcript that can reach 50 MB.
    static func scan() -> [SessionRow] {
        let manager = FileManager.default
        guard let projects = try? manager.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil)
        else { return [] }

        var files: [URL] = []
        for project in projects {
            guard let entries = try? manager.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            ) else { continue }
            files.append(contentsOf: entries.filter { $0.pathExtension == "jsonl" })
        }

        // 6k transcripts totalling gigabytes: one thread spends the whole scan
        // waiting on reads, so fan the summaries out across cores.
        var results = [SessionRow?](repeating: nil, count: files.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: files.count) { index in
            let row = summarize(files[index])
            lock.lock()
            results[index] = row
            lock.unlock()
        }
        return results.compactMap { $0 }
    }

    private static func summarize(_ file: URL) -> SessionRow? {
        let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let modified = values?.contentModificationDate ?? Date(timeIntervalSince1970: 0)

        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        var cwd: String?
        var entrypoint: String?
        var title: String?
        var firstMessage: String?
        var buffer = Data()
        var consumed = 0

        // A transcript can open with a very long line, so grow the window
        // instead of paying a 256 KB read on every one of thousands of files.
        while firstMessage == nil, buffer.count < 256 * 1024 {
            guard let chunk = try? handle.read(upToCount: 32 * 1024), !chunk.isEmpty else { break }
            buffer.append(chunk)
            guard let lastNewline = buffer.lastIndex(of: UInt8(ascii: "\n")) else { continue }
            let complete = buffer[buffer.startIndex..<lastNewline]
            for line in complete.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
                guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
                else { continue }
                cwd = cwd ?? object["cwd"] as? String
                entrypoint = entrypoint ?? object["entrypoint"] as? String
                if object["type"] as? String == "ai-title" {
                    title = title ?? (object["aiTitle"] as? String ?? object["title"] as? String)
                }
                if firstMessage == nil,
                   object["type"] as? String == "user",
                   (object["isSidechain"] as? Bool) != true {
                    let body = text(of: (object["message"] as? [String: Any])?["content"])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty, !isNoise(body) { firstMessage = body }
                }
            }
            consumed = buffer.distance(from: buffer.startIndex, to: lastNewline) + 1
            buffer = Data(buffer[buffer.index(after: lastNewline)...])
            _ = consumed
        }

        guard let opening = firstMessage else { return nil }
        if let entrypoint, entrypoint.hasPrefix("sdk-") { return nil }
        if let cwd, cwd.contains(".claude-mem") { return nil }

        return SessionRow(
            id: file.deletingPathExtension().lastPathComponent,
            title: title ?? String(opening.prefix(90)).replacingOccurrences(of: "\n", with: " "),
            cwd: cwd ?? "",
            updatedAt: modified.timeIntervalSince1970 * 1000,
            agentPreset: nil,
            agent: .claudeCode,
            logPath: file.path
        )
    }

    // Long transcripts keep the tail, which is where the session ended up.
    static func transcript(at path: String) -> (items: [TrajectoryItem], truncated: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return ([], false)
        }
        defer { try? handle.close() }

        var items: [TrajectoryItem] = []
        var pending = Data()
        var index = 0

        func ingest(_ line: Data) {
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let kind = object["type"] as? String,
                  (object["isSidechain"] as? Bool) != true
            else { return }
            let message = object["message"] as? [String: Any]
            let body = text(of: message?["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            index += 1
            let id = "cc-\(index)"
            switch kind {
            case "user":
                guard !isNoise(body) else { return }
                items.append(.user(id: id, text: body, images: []))
            case "assistant":
                items.append(.assistant(id: id, text: body))
            default:
                return
            }
            if items.count > transcriptCap { items.removeFirst(items.count - transcriptCap) }
        }

        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = pending[pending.startIndex..<newline]
                if !line.isEmpty { ingest(Data(line)) }
                pending = pending[pending.index(after: newline)...]
            }
        }
        if !pending.isEmpty { ingest(Data(pending)) }

        return (items, index > items.count)
    }
}
