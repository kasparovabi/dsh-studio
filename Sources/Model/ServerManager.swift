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

    // A launchd agent keeps the server alive so the phone can reach this Mac
    // with the app closed. Waking that agent has to come before spawning our
    // own child, otherwise both own port 3080 and launchd loops on exit 1.
    private let agentLabel = "com.kasparov.dsh-web"

    var agentInstalled: Bool {
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
        return FileManager.default.fileExists(atPath: plist.path)
    }

    @discardableResult
    func wakeAgent() -> Bool {
        guard agentInstalled else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["kickstart", "gui/\(getuid())/\(agentLabel)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

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

    // The hermes token pool rotates between a primary and a backup credential,
    // and ~/.hermes/.env keeps whichever was current when it was last written.
    // Reading the pool directly is what stops a spawned server from serving a
    // week-old token whose quota is already spent.
    private func pooledToken() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let poolData = try? Data(contentsOf: home.appendingPathComponent(".hermes/token-havuzu.json")),
              let pool = try? JSONSerialization.jsonObject(with: poolData) as? [String: Any],
              let entries = pool["tokenlar"] as? [[String: Any]] else { return nil }
        var byName: [String: String] = [:]
        for entry in entries {
            if let name = entry["ad"] as? String, let token = entry["token"] as? String {
                byName[name] = token
            }
        }
        var wanted = "birincil"
        if let stateData = try? Data(contentsOf: home.appendingPathComponent(".hermes/token-nobetci-durum.json")),
           let state = try? JSONSerialization.jsonObject(with: stateData) as? [String: Any],
           let active = state["aktif"] as? String {
            wanted = active
        }
        return byName[wanted] ?? byName["birincil"] ?? entries.first?["token"] as? String
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
        if let token = pooledToken() { env["ANTHROPIC_AUTH_TOKEN"] = token }
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
