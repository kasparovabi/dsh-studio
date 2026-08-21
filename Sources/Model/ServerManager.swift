#if os(macOS)
import Foundation

final class ServerManager {
    private var process: Process?
    let port: Int

    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-studio-server.log")

    init(port: Int) {
        self.port = port
    }

    var spawnedByApp: Bool { process != nil }

    // Every provider dsh supports reads its key from the env var named by
    // `apiKeyEnv` in ~/.dsh/settings.yaml. To match a terminal-launched dsh we
    // hand the child the login-shell environment plus every key defined in
    // ~/.hermes/.env, so any configured provider works, not just Anthropic.
    private func loginShellEnvironment() -> [String: String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: shell)
        probe.arguments = ["-lc", "env"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = FileHandle.nullDevice
        guard (try? probe.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        probe.waitUntilExit()
        guard probe.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq])
            if !key.isEmpty { result[key] = String(line[line.index(after: eq)...]) }
        }
        return result
    }

    private func readEnvFile() -> [String: String] {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes/.env")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst("export ".count)) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let value = String(line[line.index(after: eq)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { result[key] = value }
        }
        return result
    }

    func launch() throws {
        if let old = process, old.isRunning { old.terminate() }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: home + "/.npm-global/bin/dsh")
        p.arguments = ["web", "--port", String(port)]
        var env = ProcessInfo.processInfo.environment
        for (key, value) in loginShellEnvironment() { env[key] = value }
        for (key, value) in readEnvFile() { env[key] = value }
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
#endif
