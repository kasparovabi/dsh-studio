import Foundation

final class ServerManager {
    private var process: Process?
    let port: Int

    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-studio-server.log")

    init(port: Int) {
        self.port = port
    }

    var spawnedByApp: Bool { process != nil }

    private func readToken() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes/.env")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst("export ".count)) }
            guard line.hasPrefix("ANTHROPIC_AUTH_TOKEN=") else { continue }
            let raw = String(line.dropFirst("ANTHROPIC_AUTH_TOKEN=".count))
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    func launch() throws {
        if let old = process, old.isRunning { old.terminate() }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: home + "/.npm-global/bin/dsh")
        p.arguments = ["web", "--port", String(port)]
        var env = ProcessInfo.processInfo.environment
        if let token = readToken() {
            env["ANTHROPIC_AUTH_TOKEN"] = token
        }
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        env["PATH"] = "\(home)/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let logHandle = try? FileHandle(forWritingTo: logURL) {
            p.standardOutput = logHandle
            p.standardError = logHandle
        } else {
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
        }
        try p.run()
        process = p
    }

    func terminate() {
        guard let p = process, p.isRunning else { process = nil; return }
        p.terminate()
        let deadline = Date().addingTimeInterval(2)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        process = nil
    }
}
