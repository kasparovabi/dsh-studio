#if os(macOS)
import Foundation
import OSLog

enum ServerLaunchError: LocalizedError {
    case noCredential

    var errorDescription: String? {
        switch self {
        case .noCredential:
            return "No Anthropic credential to hand the server. Put a key in ~/.hermes/.env, in the token pool, or in the environment before starting it."
        }
    }
}

enum AgentWake {
    case woken
    case notInstalled
    case failed(String)
}

final class ServerManager {
    private var process: Process?
    let port: Int
    private static let log = Logger(subsystem: "com.kasparov.dsh-studio", category: "server")

    // Each run gets its own file and the last few are kept, because the previous
    // scheme truncated the log at launch and the failure worth reading was
    // usually the one from the run before.
    let logURL: URL = {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let name = "dsh-studio-server-\(stamp.string(from: Date()).replacingOccurrences(of: ":", with: "")).log"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }()

    var agentLogPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh/web.log").path
    }

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

    // A child that never exits would otherwise hang the caller forever, and both
    // of these are called from the main actor.
    private static func run(
        _ executable: String,
        _ arguments: [String],
        deadline: TimeInterval,
        capture: Bool
    ) -> (status: Int32, output: String)? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = capture ? Pipe() : nil
        task.standardOutput = pipe ?? FileHandle.nullDevice
        task.standardError = pipe ?? FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }

        let watchdog = DispatchWorkItem {
            guard task.isRunning else { return }
            log.error("\(executable, privacy: .public) exceeded \(deadline)s, terminating")
            task.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + deadline, execute: watchdog)

        var output = ""
        if let pipe {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            output = String(data: data, encoding: .utf8) ?? ""
        }
        task.waitUntilExit()
        watchdog.cancel()
        return (task.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func wakeAgent() -> AgentWake {
        guard agentInstalled else { return .notInstalled }
        guard let result = ServerManager.run(
            "/bin/launchctl",
            ["kickstart", "gui/\(getuid())/\(agentLabel)"],
            deadline: 10,
            capture: true
        ) else {
            return .failed("launchctl would not run")
        }
        if result.status == 0 { return .woken }
        ServerManager.log.error("kickstart exited \(result.status): \(result.output, privacy: .public)")
        return .failed(result.output.isEmpty ? "launchctl exited \(result.status)" : result.output)
    }

    // Every provider dsh supports reads its key from the env var named by
    // `apiKeyEnv` in ~/.dsh/settings.yaml. To match a terminal-launched dsh we
    // hand the child the login-shell environment plus every key defined in
    // ~/.hermes/.env, so any configured provider works, not just Anthropic.
    private func loginShellEnvironment() -> [String: String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let result = ServerManager.run(shell, ["-lc", "env"], deadline: 15, capture: true),
              result.status == 0 else {
            ServerManager.log.error("login shell probe failed, spawning with a bare environment")
            return [:]
        }
        var found: [String: String] = [:]
        for line in result.output.split(separator: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            if !key.isEmpty { found[key] = String(line[line.index(after: equals)...]) }
        }
        return found
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
        // The old process has to be gone before the new one asks for the port,
        // and terminate() is the sequence that actually waits for it.
        terminate()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let child = Process()
        child.executableURL = URL(fileURLWithPath: home + "/.npm-global/bin/dsh")
        child.arguments = ["web", "--port", String(port)]
        var env = ProcessInfo.processInfo.environment
        for (key, value) in loginShellEnvironment() { env[key] = value }
        for (key, value) in readEnvFile() { env[key] = value }
        // The pooled token wins over the stale copy in the env file, and the
        // API-key variable is only cleared when there is an OAuth token to use
        // in its place; clearing it unconditionally left servers with neither.
        if let token = pooledToken() {
            env["ANTHROPIC_AUTH_TOKEN"] = token
            env.removeValue(forKey: "ANTHROPIC_API_KEY")
        }
        guard env["ANTHROPIC_AUTH_TOKEN"]?.isEmpty == false || env["ANTHROPIC_API_KEY"]?.isEmpty == false else {
            throw ServerLaunchError.noCredential
        }
        env["PATH"] = "\(home)/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        child.environment = env
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let logHandle = try? FileHandle(forWritingTo: logURL) {
            child.standardOutput = logHandle
            child.standardError = logHandle
        } else {
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
        }
        try child.run()
        process = child
        ServerManager.log.info("spawned dsh on \(self.port, privacy: .public), log \(self.logURL.path, privacy: .public)")
        pruneOldLogs()
    }

    private func pruneOldLogs() {
        let directory = FileManager.default.temporaryDirectory
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return }
        let logs = entries
            .filter { $0.lastPathComponent.hasPrefix("dsh-studio-server-") }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        for stale in logs.dropFirst(5) { try? FileManager.default.removeItem(at: stale) }
    }

    func terminate() {
        guard let child = process, child.isRunning else { process = nil; return }
        child.terminate()
        let deadline = Date().addingTimeInterval(2)
        while child.isRunning && Date() < deadline { usleep(50_000) }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        process = nil
    }
}
#endif
