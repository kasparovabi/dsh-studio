import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
    var label: String { self == .light ? "Light" : "Dark" }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

// One entry per machine running dsh. The phone moves between them; the desk app
// only ever talks to its own, so this list is furniture the phone layer shows.
struct SavedServer: Identifiable, Codable, Hashable {
    var name: String
    var host: String

    var id: String { host }

    private static let key = "dsh.servers"

    static func load() -> [SavedServer] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedServer].self, from: data) else { return [] }
        return decoded
    }

    static func save(_ servers: [SavedServer]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct SessionRow: Identifiable, Hashable {
    let id: String
    var title: String
    var cwd: String
    var updatedAt: Double
    var agentPreset: String?
    var turns: Int = 0
    var running: Bool = false

    var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    var bucket: SessionBucket {
        guard updatedAt > 0 else { return .older }
        let date = Date(timeIntervalSince1970: updatedAt / 1000)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()), date > weekAgo {
            return .lastWeek
        }
        return .older
    }

    var relativeTime: String {
        guard updatedAt > 0 else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: Date(timeIntervalSince1970: updatedAt / 1000), relativeTo: Date())
    }
}

enum SessionBucket: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case lastWeek = "Last 7 days"
    case older = "Older"

    var id: String { rawValue }
}

struct EffortOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct ModelOption: Identifiable, Hashable {
    var id: String { "\(provider)/\(model)" }
    let provider: String
    let providerName: String
    let model: String
    let modelName: String
    var efforts: [EffortOption] = []
    var defaultEffort: String?
}

struct ApprovalRequest: Identifiable, Equatable {
    let id: String
    let rpcId: String
    let sessionId: String
    let toolName: String
    let reason: String?
    let callId: String?
}

extension String {
    var sanitizedForDisplay: String {
        String(unicodeScalars.filter { scalar in
            !scalar.properties.isBidiControl
                && !(scalar.value < 0x20 && scalar != "\n" && scalar != "\t")
                && !(0x2066...0x2069).contains(scalar.value)
        })
    }
}

struct QueueItem: Identifiable, Equatable {
    let id: String
    let placement: String
    let text: String
}

struct PermissionSelect: Equatable {
    let options: [String]
    var current: String
}

struct PresetOption: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?
    let isDefault: Bool
}

struct SkillInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let description: String
}

struct SubagentEntry: Identifiable, Equatable {
    let id: String
    let mode: String
    let activity: String
    let label: String
}

struct JobView: Identifiable, Equatable {
    let id: String
    let kind: String
    let label: String
    let status: String
    let detail: String?
}

struct GoalState: Equatable {
    let id: String
    let revision: Int
    let objective: String
    let phase: String
    let blockedMessage: String?
    let maxRounds: Int
    let roundsStarted: Int
}

struct ContextPressure: Equatable {
    let tokens: Int
    let window: Int

    var fraction: Double { min(1, Double(tokens) / Double(window)) }
}

struct PendingImage: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let mediaType: String
    let data: Data
    let preview: PlatformImage?
}

struct QuestionOption: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let description: String?
}

struct QuestionItem: Identifiable {
    let id: String
    let question: String
    let header: String?
    let detail: String?
    let options: [QuestionOption]
    let multiSelect: Bool
    let approveLabel: String?
}

struct QuestionRequest: Identifiable {
    var id: String { rpcId }
    let rpcId: String
    let sessionId: String
    let items: [QuestionItem]
}

@MainActor
final class StreamState: ObservableObject {
    @Published var text = ""
    @Published var thinking = ""

    func clear() {
        text = ""
        thinking = ""
    }
}

struct CredentialRow: Identifiable, Equatable {
    var id: String { ref }
    let ref: String
    let label: String
    let provider: String
    var configured: Bool
    var writable: Bool
    var source: String?
}

@MainActor
final class AppModel: ObservableObject {
    static let knownCredentials: [CredentialRow] = [
        CredentialRow(ref: "ANTHROPIC_AUTH_TOKEN", label: "Anthropic", provider: "anthropic", configured: false, writable: true, source: nil),
        CredentialRow(ref: "DEEPSEEK_API_KEY", label: "DeepSeek", provider: "deepseek-official", configured: false, writable: true, source: nil),
        CredentialRow(ref: "OPENAI_API_KEY", label: "OpenAI", provider: "openai", configured: false, writable: true, source: nil),
        CredentialRow(ref: "GEMINI_API_KEY", label: "Google Gemini", provider: "gemini", configured: false, writable: true, source: nil),
        CredentialRow(ref: "OPENROUTER_API_KEY", label: "OpenRouter", provider: "openrouter", configured: false, writable: true, source: nil),
        CredentialRow(ref: "MOONSHOT_API_KEY", label: "Moonshot / Kimi", provider: "moonshot", configured: false, writable: true, source: nil),
        CredentialRow(ref: "ZHIPUAI_API_KEY", label: "Zhipu / GLM", provider: "zhipu", configured: false, writable: true, source: nil),
        CredentialRow(ref: "XAI_API_KEY", label: "xAI Grok", provider: "xai", configured: false, writable: true, source: nil),
    ]

    enum ServerState: Equatable {
        case idle, connecting, launching, ready
        case failed(String)
    }

    static weak var shared: AppModel?

    @Published var serverState: ServerState = .idle
    @Published var sessions: [SessionRow] = []
    @Published var selected: String?
    @Published var items: [TrajectoryItem] = []
    @Published var stats = SessionStats()
    @Published var running = false
    @Published var provider = ""
    @Published var model = ""
    @Published var hostCwd = ""
    @Published var probeFailure = ""
    @Published var reasoningEffort: String?
    @Published var modelOptions: [ModelOption] = []
    @Published var approvals: [ApprovalRequest] = []
    @Published var questions: [QuestionRequest] = []
    var question: QuestionRequest? { questions.first { $0.sessionId == selected } }
    @Published var queueItems: [QueueItem] = []
    @Published var composer = ""
    @Published var scrollPin = 0
    let streamState = StreamState()
    @Published var lastError: String?
    @Published var wsConnected = false
    @Published var pendingImages: [PendingImage] = []
    @Published var attachmentImages: [String: PlatformImage] = [:]
    @Published var contextPressure: ContextPressure?
    @Published var jobs: [JobView] = []
    @Published var subagents: [SubagentEntry] = []
    @Published var subagentSheet: SubagentEntry?
    @Published var subagentHistory: [(String, String)] = []
    @Published var goal: GoalState?
    @Published var permission: PermissionSelect?
    @Published var presetOptions: [PresetOption] = []
    @Published var agentPreset: String?
    @Published var skills: [SkillInfo] = []
    @Published var recoveredHistory = false
    @Published var skillsSheetOpen = false
    @Published var settingsOpen = false
    @Published var credentialRows: [CredentialRow] = []
    @Published var credentialDrafts: [String: String] = [:]
    @Published var settingsProvider = ""
    @Published var settingsModel = ""
    @Published var settingsBusy = false
    @Published var settingsNotice: String?
    private var defaultModelRevision: Int?
    @Published var goalSheetOpen = false
    @Published var goalDraft = ""
    @Published var projectFilter: String?
    @Published var searchQuery = ""

    var projectCounts: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for session in sessions { counts[session.project, default: 0] += 1 }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { (name: $0.key, count: $0.value) }
    }
    @Published var searchResults: [String: String]?
    @Published var renameTarget: SessionRow?
    @Published var renameDraft = ""

    private var attachmentFetches: Set<String> = []
    private var appendedIDs: Set<String> = []
    private var toolIndex: [String: Int] = [:]
    private var searchTask: Task<Void, Never>?
    private var sessionsRefreshTask: Task<Void, Never>?
    private var frameConsumer: Task<Void, Never>?
    private var frameContinuation: AsyncStream<[String: Any]>.Continuation?

    private(set) var port: Int = {
        if let raw = Int(ProcessInfo.processInfo.environment["DSH_STUDIO_PORT"] ?? ""),
           (1...65535).contains(raw) { return raw }
        let stored = UserDefaults.standard.integer(forKey: "dsh.port")
        return (1...65535).contains(stored) ? stored : 3080
    }()

    // An address is written host:port everywhere else, so it arrives that way
    // here too. The port lives apart from the host, which is why pasting the
    // whole thing into the host field used to produce `addr:3080:3080`.
    static func splitAddress(_ raw: String, fallbackPort: Int) -> (host: String, port: Int) {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard let colon = value.lastIndex(of: ":") else { return (value, fallbackPort) }
        let tail = String(value[value.index(after: colon)...])
        guard let parsed = Int(tail), (1...65535).contains(parsed) else { return (value, fallbackPort) }
        return (String(value[..<colon]), parsed)
    }
    // The desk app owns the server it talks to, so loopback is the only
    // sensible address there. The phone reaches one over the tailnet, so its
    // layer overwrites this before connecting.
    @Published var host: String = UserDefaults.standard.string(forKey: "dsh.host") ?? "127.0.0.1"
    @Published var appearance: Appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "dsh.appearance") ?? "") ?? .light {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "dsh.appearance") }
    }
    @Published var savedServers: [SavedServer] = SavedServer.load() {
        didSet { SavedServer.save(savedServers) }
    }
    lazy var client = DshClient(host: host, port: port)
    #if os(macOS)
    private lazy var server = ServerManager(port: port)
    #endif
    private var socket: EventSocket?
    private var loadGeneration = 0
    private var projectionSnapshots: [String: [String: Any]] = [:]
    private var reconnectInFlight = false
    private var errorGeneration = 0

    var serverStatusText: String {
        switch serverState {
        case .idle: return "Idle"
        case .connecting: return "Connecting…"
        case .launching: return "Starting dsh server…"
        case .ready: return wsConnected ? "Connected" : "Stream lost"
        case .failed(let m): return m
        }
    }

    init() {
        AppModel.shared = self
    }

    func shutdownIfSpawned() {
        #if os(macOS)
        if server.spawnedByApp { server.terminate() }
        #endif
    }

    func bootstrap() {
        guard serverState == .idle else { return }
        Task { await connect() }
    }

    // Coming back to a socket that quietly died looks exactly like coming back
    // to a working one, so the connection is rebuilt rather than trusted. The
    // reconnect re-reads the open session, which brings back whatever was
    // missed while the app was away.
    func resumeIfStale() {
        guard serverState != .idle else { return bootstrap() }
        guard !wsConnected else { return }
        Task { await connect() }
    }

    // Each machine runs its own dsh with its own sessions, so moving between
    // them is a reconnect: drop the socket and every session-shaped thing on
    // screen, then come up against the new address.
    func isConnected(to address: String) -> Bool {
        let parsed = AppModel.splitAddress(address, fallbackPort: port)
        return parsed.host == host && parsed.port == port
    }

    var serverName: String {
        savedServers.first(where: { isConnected(to: $0.host) })?.name ?? host
    }

    func switchServer(to address: String) async {
        let parsed = AppModel.splitAddress(address, fallbackPort: port)
        guard !parsed.host.isEmpty else { return }
        guard parsed.host != host || parsed.port != port else { return }
        socket?.stop()
        socket = nil
        sessions = []
        selected = nil
        items = []
        projectionSnapshots = [:]
        hostCwd = ""
        serverState = .idle
        host = parsed.host
        port = parsed.port
        UserDefaults.standard.set(parsed.host, forKey: "dsh.host")
        UserDefaults.standard.set(parsed.port, forKey: "dsh.port")
        await connect()
    }

    func connect() async {
        client.host = host
        client.port = port
        serverState = .connecting
        for attempt in 0..<3 {
            if await probe() {
                await becomeReady()
                return
            }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 300_000_000) }
        }
        // Only the machine running the server can start one. From the phone a
        // silent server is the end of the road, so say so instead of stalling.
        #if os(macOS)
        serverState = .launching
        do {
            try server.launch()
        } catch {
            serverState = .failed("failed to launch dsh: \(error.localizedDescription)")
            return
        }
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await probe() {
                await becomeReady()
                return
            }
        }
        serverState = .failed("dsh did not come up within 30s. See \(server.logURL.path)")
        #else
        serverState = .failed("No dsh server answered at \(host):\(port)\n\(probeFailure)")
        #endif
    }

    private func probe() async -> Bool {
        do {
            guard let host = try await client.call("host.describe") as? [String: Any] else {
                probeFailure = "unexpected reply"
                return false
            }
            probeFailure = ""
            return host["version"] != nil || host["cwd"] != nil
        } catch {
            let ns = error as NSError
            probeFailure = "\(ns.domain) \(ns.code) \(ns.localizedDescription)"
            return false
        }
    }

    private func becomeReady() async {
        serverState = .ready
        if let host = (try? await client.call("host.describe")) as? [String: Any] {
            provider = host["provider"] as? String ?? ""
            model = host["model"] as? String ?? ""
            hostCwd = host["cwd"] as? String ?? ""
        }
        approvals = []
        questions = []
        let previouslySelected = selected
        await refreshSessions()
        if let sel = previouslySelected, sessions.contains(where: { $0.id == sel }) {
            await select(sel)
        }
        openSocket()
        await loadPresets()
    }

    // dsh ships its four built-in presets with Chinese copy. The rest of this app
    // is English, so the shipped ones are relabelled here. Presets the user wrote
    // keep whatever they named them.
    private static let shippedPresetCopy: [String: (String, String)] = [
        "standard": ("Standard", "Full coding agent with file editing, shell, file and web search, skills, plans, goals, subagents and workflows."),
        "code": ("PTC", "Everything in Standard, with tools exposed through the Code Mode SDK so the model composes multi-step work as one TypeScript program."),
        "minimal": ("Minimal", "A two-tool coding agent with nothing but a persistent bash and str_replace_editor."),
        "cordis": ("Authoring", "For writing your own agent presets. Everything in Standard, plus runtime inspection, plugin experiments and authoring guidance."),
    ]

    private func loadPresets() async {
        guard let value = (try? await client.call("agentPreset.list")) as? [String: Any] else { return }
        presetOptions = (value["presets"] as? [[String: Any]] ?? []).compactMap { p in
            guard let pid = p["id"] as? String, p["broken"] == nil else { return nil }
            let shipped = (p["trust"] as? String) == "system" ? AppModel.shippedPresetCopy[pid] : nil
            return PresetOption(
                id: pid,
                name: shipped?.0 ?? (p["name"] as? String ?? pid),
                description: shipped?.1 ?? (p["description"] as? String),
                isDefault: p["isDefault"] as? Bool ?? false
            )
        }
    }

    func selectPermission(_ value: String) {
        guard let sessionId = selected else { return }
        Task {
            do {
                _ = try await client.call("commands/execute", [
                    "args": ["agentId": sessionId, "line": "/permission \(value)"],
                ])
                guard sessionId == selected else { return }
                if var current = permission {
                    current.current = value
                    permission = current
                }
            } catch {
                report("permission switch failed: \(error.localizedDescription)")
            }
        }
    }

    func selectPreset(_ option: PresetOption) {
        guard let sessionId = selected else { return }
        Task {
            do {
                _ = try await client.call("agentPreset.select", [
                    "sessionId": sessionId,
                    "agentPreset": option.id,
                ])
                guard sessionId == selected else { return }
                agentPreset = option.id
                await refreshSessions()
            } catch {
                report("preset switch failed: \(error.localizedDescription)")
            }
        }
    }

    func openSkills() {
        guard let sessionId = selected else { return }
        skillsSheetOpen = true
        skills = []
        Task {
            do {
                let value = try await client.call("skill.list", ["sessionId": sessionId]) as? [String: Any]
                skills = (value?["skills"] as? [[String: Any]] ?? []).compactMap { s in
                    guard let name = s["name"] as? String else { return nil }
                    return SkillInfo(name: name, description: s["description"] as? String ?? "")
                }
            } catch {
                report("skill list failed: \(error.localizedDescription)")
            }
        }
    }

    func openSettings() {
        settingsOpen = true
        settingsNotice = nil
        Task { await loadSettings() }
    }

    func loadSettings() async {
        var refs = AppModel.knownCredentials.map { $0.ref }
        var labels: [String: (String, String)] = [:]
        for row in AppModel.knownCredentials { labels[row.ref] = (row.label, row.provider) }

        if let value = try? await client.call("settings.describe") as? [String: Any],
           let namespaces = value["namespaces"] as? [[String: Any]] {
            for ns in namespaces {
                let name = ns["ns"] as? String
                let doc = ns["value"] as? [String: Any]
                if name == "agent-default-model" {
                    settingsProvider = doc?["provider"] as? String ?? settingsProvider
                    settingsModel = doc?["model"] as? String ?? settingsModel
                    defaultModelRevision = ns["revision"] as? Int
                }
                for found in Self.apiKeyEnvRefs(in: doc) where !refs.contains(found) {
                    refs.append(found)
                    labels[found] = (found, name ?? "")
                }
            }
        }

        var rows: [CredentialRow] = []
        if let value = try? await client.call("credentials.describe", ["refs": refs]) as? [String: Any],
           let creds = value["credentials"] as? [String: Any] {
            for ref in refs {
                let info = creds[ref] as? [String: Any]
                let meta = labels[ref] ?? (ref, "")
                rows.append(CredentialRow(
                    ref: ref,
                    label: meta.0,
                    provider: meta.1,
                    configured: info?["configured"] as? Bool ?? false,
                    writable: info?["writable"] as? Bool ?? true,
                    source: info?["source"] as? String
                ))
            }
        } else {
            rows = AppModel.knownCredentials
        }
        credentialRows = rows
    }

    private static func apiKeyEnvRefs(in doc: [String: Any]?) -> [String] {
        guard let doc else { return [] }
        var refs: [String] = []
        if let direct = doc["apiKeyEnv"] as? String, !direct.isEmpty { refs.append(direct) }
        if let providers = doc["providers"] as? [String: Any] {
            for (_, p) in providers {
                if let env = (p as? [String: Any])?["apiKeyEnv"] as? String, !env.isEmpty {
                    refs.append(env)
                }
            }
        }
        return refs
    }

    func saveCredential(_ ref: String) {
        let value = (credentialDrafts[ref] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        settingsBusy = true
        settingsNotice = nil
        Task {
            do {
                _ = try await client.call("credentials.set", ["ref": ref, "value": value])
                credentialDrafts[ref] = ""
                settingsNotice = "\(ref) saved"
                await loadSettings()
            } catch {
                settingsNotice = "Could not save \(ref): \(error.localizedDescription)"
            }
            settingsBusy = false
        }
    }

    func clearCredential(_ ref: String) {
        settingsBusy = true
        settingsNotice = nil
        Task {
            do {
                _ = try await client.call("credentials.unset", ["ref": ref])
                credentialDrafts[ref] = ""
                settingsNotice = "\(ref) removed"
                await loadSettings()
            } catch {
                settingsNotice = "Could not remove \(ref): \(error.localizedDescription)"
            }
            settingsBusy = false
        }
    }

    func saveDefaultModel() {
        let prov = settingsProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        let mdl = settingsModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prov.isEmpty, !mdl.isEmpty else { return }
        settingsBusy = true
        settingsNotice = nil
        Task {
            do {
                var payload: [String: Any] = [
                    "ns": "agent-default-model",
                    "patch": ["provider": prov, "model": mdl],
                ]
                if let rev = defaultModelRevision { payload["revision"] = rev }
                _ = try await client.call("settings.update", payload)
                settingsNotice = "Default model saved"
                await loadSettings()
            } catch {
                settingsNotice = "Could not save default model: \(error.localizedDescription)"
            }
            settingsBusy = false
        }
    }

    private func scheduleSessionsRefresh() {
        sessionsRefreshTask?.cancel()
        sessionsRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await refreshSessions()
        }
    }

    func refreshSessions() async {
        guard let value = (try? await client.call("session.list")) as? [String: Any],
              let list = value["items"] as? [[String: Any]] else { return }
        sessions = list.compactMap { item in
            guard let id = item["sessionId"] as? String else { return nil }
            let values = (item["projections"] as? [String: Any])?["values"] as? [String: Any]
            if let values { projectionSnapshots[id] = values }
            var title = values?["title"] as? String
            if title == nil, let t = (values?["title"] as? [String: Any])?["title"] as? String { title = t }
            let stats = values?["sessionStats"] as? [String: Any]
            return SessionRow(
                id: id,
                title: title ?? "Untitled session",
                cwd: item["cwd"] as? String ?? "",
                updatedAt: item["updatedAt"] as? Double ?? 0,
                agentPreset: item["agentPreset"] as? String,
                turns: stats?["turns"] as? Int ?? 0,
                running: item["running"] as? Bool ?? false
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
        let liveIDs = Set(sessions.map { $0.id })
        projectionSnapshots = projectionSnapshots.filter { liveIDs.contains($0.key) }
        if selected == nil, let first = sessions.first {
            await select(first.id)
        }
    }

    func select(_ id: String) async {
        selected = id
        lastError = nil
        items = []
        appendedIDs = []
        toolIndex = [:]
        stats = SessionStats()
        running = false
        streamState.clear()
        queueItems = []
        contextPressure = nil
        goal = nil
        jobs = []
        subagents = []
        subagentSheet = nil
        subagentHistory = []
        pendingImages = []
        permission = nil
        recoveredHistory = false
        attachmentImages = [:]
        attachmentFetches = []
        agentPreset = sessions.first(where: { $0.id == id })?.agentPreset
        if let snapshot = projectionSnapshots[id] {
            applyProjection(key: "tokenUsage", value: snapshot["tokenUsage"] ?? [:])
            applyProjection(key: "sessionStats", value: snapshot["sessionStats"] ?? [:])
            applyProjection(key: "contextPressure", value: snapshot["contextPressure"] ?? [:])
            applyProjection(key: "goal", value: snapshot["goal"] ?? NSNull())
            applyProjection(key: "permissions", value: snapshot["permissions"] ?? [:])
        }
        loadGeneration += 1
        let generation = loadGeneration
        await loadModels(id, generation: generation)
        await loadHistory(id, generation: generation)
        refreshSubagents()
    }

    private func loadModels(_ id: String, generation: Int) async {
        guard let value = (try? await client.call("session.models", ["sessionId": id])) as? [String: Any] else { return }
        guard generation == loadGeneration else { return }
        if let current = value["current"] as? [String: Any] {
            provider = current["provider"] as? String ?? provider
            model = current["model"] as? String ?? model
            reasoningEffort = current["reasoningEffort"] as? String
        }
        var options: [ModelOption] = []
        for group in value["groups"] as? [[String: Any]] ?? [] {
            let pid = group["id"] as? String ?? ""
            let pname = group["name"] as? String ?? pid
            for m in group["models"] as? [[String: Any]] ?? [] {
                guard let mid = m["id"] as? String else { continue }
                var option = ModelOption(provider: pid, providerName: pname, model: mid, modelName: m["name"] as? String ?? mid)
                if let reasoning = m["reasoning"] as? [String: Any] {
                    option.efforts = (reasoning["efforts"] as? [[String: Any]] ?? []).compactMap { e in
                        guard let eid = e["id"] as? String else { return nil }
                        return EffortOption(id: eid, name: e["name"] as? String ?? eid)
                    }
                    option.defaultEffort = reasoning["defaultEffort"] as? String
                }
                options.append(option)
            }
        }
        modelOptions = options
    }

    var currentModelOption: ModelOption? {
        modelOptions.first { $0.provider == provider && $0.model == model }
    }

    func selectModel(_ option: ModelOption) {
        guard let sessionId = selected else { return }
        Task {
            do {
                _ = try await client.call("session.selectModel", [
                    "sessionId": sessionId,
                    "provider": option.provider,
                    "model": option.model,
                ])
                guard sessionId == selected else { return }
                provider = option.provider
                model = option.model
                reasoningEffort = nil
            } catch {
                report("model selection failed: \(error.localizedDescription)")
            }
        }
    }

    func selectEffort(_ effortId: String) {
        guard let sessionId = selected, !provider.isEmpty, !model.isEmpty else { return }
        Task {
            do {
                let value = try await client.call("session.selectModel", [
                    "sessionId": sessionId,
                    "provider": provider,
                    "model": model,
                    "reasoningEffort": effortId,
                ]) as? [String: Any]
                guard sessionId == selected else { return }
                let chosen = value?["selected"] as? [String: Any]
                reasoningEffort = chosen?["reasoningEffort"] as? String ?? effortId
            } catch {
                report("effort selection failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadHistory(_ id: String, generation: Int) async {
        do {
            let value = try await client.call("session.history", ["sessionId": id])
            guard generation == loadGeneration else { return }
            let wrapped = (value as? [String: Any])?["events"] as? [[String: Any]] ?? []
            for wrapper in wrapped {
                if let event = wrapper["event"] as? [String: Any] {
                    reduce(event: event, live: false)
                }
            }
        } catch {
            await loadHistoryFromDisk(id, generation: generation, reason: error.localizedDescription)
        }
    }

    // The salvage path reads the log off the disk the server writes to, which
    // only the machine hosting it can reach.
    private func loadHistoryFromDisk(_ id: String, generation: Int, reason: String) async {
        #if os(macOS)
        let events = await Task.detached(priority: .userInitiated) {
            SessionLogReader.events(for: id)
        }.value
        #else
        let events: [[String: Any]] = []
        #endif
        guard generation == loadGeneration else { return }
        guard !events.isEmpty else {
            report("history load failed: \(reason)")
            return
        }
        for event in events {
            reduce(event: event, live: false)
        }
        recoveredHistory = true
    }

    // Typing while the agent works means "take this into account now", the way
    // a terminal harness treats it. Queueing is still there, but it is the
    // deliberate choice rather than what a plain Return does.
    func send(mode requested: String? = nil) {
        let mode = requested ?? (running ? "steer" : "queue")
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        guard !text.isEmpty || !images.isEmpty, let sessionId = selected else { return }
        composer = ""
        pendingImages = []
        lastError = nil
        scrollPin += 1
        var content: [[String: Any]] = images.map {
            ["type": "image", "data": $0.data.base64EncodedString(), "mediaType": $0.mediaType, "name": $0.name]
        }
        if !text.isEmpty {
            content.append(["type": "text", "text": text])
        }
        Task {
            do {
                _ = try await client.call("session.prompt", [
                    "sessionId": sessionId,
                    "mode": mode,
                    "content": content,
                ])
            } catch {
                report("send failed: \(error.localizedDescription)")
                if composer.isEmpty { composer = text }
                if pendingImages.isEmpty { pendingImages = images }
            }
        }
    }

    static func imageMediaType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return nil
        }
    }

    // A prompt carries text and images and nothing else, so anything else picked
    // here goes in as a path. The agent runs on this machine and reads it with
    // its own tools, which is also what a terminal harness does with a path.
    func attachPath(_ path: String) {
        let quoted = path.contains(" ") ? "\"\(path)\"" : path
        if composer.isEmpty {
            composer = quoted
        } else if composer.hasSuffix(" ") || composer.hasSuffix("\n") {
            composer += quoted
        } else {
            composer += " " + quoted
        }
    }

    // The phone is not the machine the agent runs on, so a path picked there
    // points at nothing it can open. Text and images are the whole wire format,
    // which leaves carrying the contents over as the only way to hand it a file.
    func attachText(name: String, body: String) {
        let block = "\(name)\n```\n\(body.trimmingCharacters(in: .newlines))\n```"
        composer = composer.isEmpty ? block : composer + "\n\n" + block
    }

    // A file panel and a pasteboard are desk furniture. The phone reaches its
    // pictures through a photo picker in its own layer instead.
    #if os(macOS)
    func attachImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        panel.begin { [weak self] resp in
            guard resp == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in
                for url in urls {
                    guard let mediaType = AppModel.imageMediaType(forExtension: url.pathExtension) else {
                        self?.attachPath(url.path)
                        continue
                    }
                    guard let data = try? Data(contentsOf: url) else {
                        self?.report("could not read \(url.lastPathComponent)")
                        continue
                    }
                    self?.pendingImages.append(PendingImage(
                        name: url.lastPathComponent,
                        mediaType: mediaType,
                        data: data,
                        preview: PlatformImage(data: data)
                    ))
                }
            }
        }
    }
    #endif

    func addPendingImage(name: String, mediaType: String, data: Data) {
        pendingImages.append(PendingImage(
            name: name,
            mediaType: mediaType,
            data: data,
            preview: PlatformImage(data: data)
        ))
    }

    // The field editor swallows Cmd V for text, so the composer hands the event
    // here first and only lets it through when the pasteboard holds no image.
    #if os(macOS)
    @discardableResult
    func pasteImageFromClipboard() -> Bool {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            var handled = false
            for url in urls where url.isFileURL {
                guard let type = AppModel.imageMediaType(forExtension: url.pathExtension),
                      let data = try? Data(contentsOf: url) else {
                    attachPath(url.path)
                    handled = true
                    continue
                }
                pendingImages.append(PendingImage(
                    name: url.lastPathComponent,
                    mediaType: type,
                    data: data,
                    preview: PlatformImage(data: data)
                ))
                handled = true
            }
            if handled { return true }
        }
        if let data = pasteboard.data(forType: .png) {
            pendingImages.append(PendingImage(
                name: "Pasted image.png",
                mediaType: "image/png",
                data: data,
                preview: PlatformImage(data: data)
            ))
            return true
        }
        // A screenshot lands as TIFF, which no provider accepts, so re-encode it.
        if let tiff = pasteboard.data(forType: .tiff),
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            pendingImages.append(PendingImage(
                name: "Pasted image.png",
                mediaType: "image/png",
                data: png,
                preview: PlatformImage(data: png)
            ))
            return true
        }
        return false
    }
    #endif

    func removePendingImage(_ image: PendingImage) {
        pendingImages.removeAll { $0.id == image.id }
    }

    func loadAttachment(_ attachmentId: String) {
        guard let sessionId = selected,
              attachmentImages[attachmentId] == nil,
              !attachmentFetches.contains(attachmentId) else { return }
        attachmentFetches.insert(attachmentId)
        Task {
            do {
                let value = try await client.call("session.attachment", [
                    "sessionId": sessionId,
                    "attachmentId": attachmentId,
                ]) as? [String: Any]
                if let b64 = value?["data"] as? String,
                   let data = Data(base64Encoded: b64),
                   let image = PlatformImage(data: data) {
                    attachmentImages[attachmentId] = image
                }
            } catch {
                report("attachment load failed: \(error.localizedDescription)")
            }
            attachmentFetches.remove(attachmentId)
        }
    }

    func removeQueued(_ item: QueueItem) {
        guard let sessionId = selected else { return }
        Task {
            do {
                _ = try await client.call("session.updateQueue", [
                    "sessionId": sessionId,
                    "itemId": item.id,
                    "action": ["kind": "remove"],
                ])
            } catch {
                report("queue update failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshSubagents() {
        guard let sessionId = selected else { return }
        Task {
            guard let value = (try? await client.call("subagent.list", ["parentSessionId": sessionId])) as? [String: Any],
                  sessionId == selected else { return }
            subagents = (value["entries"] as? [[String: Any]] ?? []).compactMap { entry in
                guard entry["kind"] as? String == "child",
                      let childId = entry["id"] as? String else { return nil }
                return SubagentEntry(
                    id: childId,
                    mode: entry["mode"] as? String ?? "one-shot",
                    activity: entry["activity"] as? String ?? "inactive",
                    label: entry["label"] as? String ?? String(childId.suffix(8))
                )
            }
        }
    }

    func openSubagent(_ entry: SubagentEntry) {
        guard let sessionId = selected else { return }
        subagentSheet = entry
        subagentHistory = []
        Task {
            do {
                let value = try await client.call("subagent.history", [
                    "parentSessionId": sessionId,
                    "childSessionId": entry.id,
                    "mode": entry.mode,
                ]) as? [String: Any]
                var rows: [(String, String)] = []
                for wrapper in value?["events"] as? [[String: Any]] ?? [] {
                    guard let event = wrapper["event"] as? [String: Any],
                          let type = event["type"] as? String else { continue }
                    let data = event["data"] as? [String: Any] ?? [:]
                    if type == "user/message", let text = EventReducer.messageText(data) {
                        rows.append(("user", text))
                    } else if type == "assistant/message", let text = EventReducer.messageText(data) {
                        rows.append(("agent", text))
                    }
                }
                subagentHistory = rows
            } catch {
                report("subagent history failed: \(error.localizedDescription)")
            }
        }
    }

    func interruptSubagent(_ entry: SubagentEntry) {
        guard let sessionId = selected else { return }
        Task {
            do {
                _ = try await client.call("subagent.interrupt", [
                    "parentSessionId": sessionId,
                    "childSessionId": entry.id,
                    "mode": "continuable",
                ])
                refreshSubagents()
            } catch {
                report("subagent interrupt failed: \(error.localizedDescription)")
            }
        }
    }

    func createGoal() {
        let objective = goalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        goalSheetOpen = false
        goalDraft = ""
        guard !objective.isEmpty, let sessionId = selected else { return }
        Task {
            do {
                _ = try await client.call("goal.create", ["sessionId": sessionId, "objective": objective])
            } catch {
                report("goal create failed: \(error.localizedDescription)")
            }
        }
    }

    func goalAction(_ action: String) {
        guard let sessionId = selected, let current = goal else { return }
        Task {
            do {
                _ = try await client.call("goal.\(action)", [
                    "sessionId": sessionId,
                    "ref": ["id": current.id, "revision": current.revision],
                ])
            } catch {
                report("goal \(action) failed: \(error.localizedDescription)")
            }
        }
    }

    func runSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            do {
                let value = try await client.call("session.search", ["query": query]) as? [String: Any]
                guard query == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                var results: [String: String] = [:]
                for item in value?["items"] as? [[String: Any]] ?? [] {
                    if let id = item["sessionId"] as? String {
                        results[id] = item["snippet"] as? String ?? ""
                    }
                }
                searchResults = results
            } catch {
                if query == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) {
                    searchResults = [:]
                }
            }
        }
    }

    func beginRename(_ session: SessionRow) {
        renameTarget = session
        renameDraft = session.title
    }

    func commitRename() {
        guard let target = renameTarget else { return }
        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !title.isEmpty, title != target.title else { return }
        Task {
            do {
                _ = try await client.call("session.rename", ["sessionId": target.id, "title": title])
                await refreshSessions()
            } catch {
                report("rename failed: \(error.localizedDescription)")
            }
        }
    }

    // dsh has no delete over the wire, so a conversation is removed the only way
    // there is: its folder under ~/.dsh/sessions. That folder is named after the
    // working directory in a shape this app should not try to reproduce, so the
    // id is looked up instead. It follows that only the machine running the
    // server can do this, which is why the phone has no delete.
    #if os(macOS)
    func delete(_ session: SessionRow) {
        guard let folder = AppModel.sessionFolder(for: session.id) else {
            report("could not find the folder for this session")
            return
        }
        do {
            try FileManager.default.removeItem(at: folder)
        } catch {
            report("delete failed: \(error.localizedDescription)")
            return
        }
        Task {
            if selected == session.id {
                selected = nil
                items = []
            }
            await refreshSessions()
            if selected == nil, let first = sessions.first { await select(first.id) }
        }
    }

    static func sessionFolder(for id: String) -> URL? {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dsh/sessions")
        let manager = FileManager.default
        guard let projects = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        for project in projects {
            let candidate = project.appendingPathComponent(id)
            if manager.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
    #endif

    func fork(_ session: SessionRow) {
        Task {
            do {
                let value = try await client.call("session.fork", ["sessionId": session.id]) as? [String: Any]
                await refreshSessions()
                if let child = value?["sessionId"] as? String {
                    if !sessions.contains(where: { $0.id == child }) {
                        sessions.insert(SessionRow(id: child, title: session.title, cwd: session.cwd, updatedAt: 0, agentPreset: session.agentPreset), at: 0)
                    }
                    await select(child)
                }
            } catch {
                report("fork failed: \(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        guard let sessionId = selected else { return }
        Task {
            do {
                _ = try await client.call("session.cancel", ["sessionId": sessionId])
            } catch {
                report("cancel failed: \(error.localizedDescription)")
            }
        }
    }

    func respond(to approval: ApprovalRequest, outcome: String) {
        approvals.removeAll { $0.id == approval.id }
        Task {
            do {
                try await client.respond(rpcId: approval.rpcId, value: [
                    "sessionId": approval.sessionId,
                    "approvalId": approval.id,
                    "outcome": outcome,
                ])
            } catch {
                report("approval response failed: \(error.localizedDescription)")
            }
        }
    }

    #if os(macOS)
    func newSession() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open here"
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.createSession(cwd: url.path)
            }
        }
    }
    #endif

    func createSession(cwd: String) async {
        do {
            let value = try await client.call("session.create", ["cwd": cwd]) as? [String: Any]
            await refreshSessions()
            if let id = value?["sessionId"] as? String {
                if !sessions.contains(where: { $0.id == id }) {
                    sessions.insert(SessionRow(id: id, title: "Untitled session", cwd: cwd, updatedAt: 0, agentPreset: nil), at: 0)
                }
                await select(id)
            }
        } catch {
            report("session create failed: \(error.localizedDescription)")
        }
    }

    private func openSocket() {
        socket?.stop()
        frameContinuation?.finish()
        frameConsumer?.cancel()
        guard let wsURL = URL(string: "ws://\(host):\(port)/api/events.mux") else { return }
        let (stream, continuation) = AsyncStream.makeStream(of: [String: Any].self)
        frameContinuation = continuation
        frameConsumer = Task { @MainActor [weak self] in
            for await frame in stream {
                self?.handle(frame: frame)
            }
        }
        let s = EventSocket(url: wsURL) { frame in
            continuation.yield(frame)
        } onState: { [weak self] up in
            Task { @MainActor in
                self?.wsConnected = up
                if !up { self?.scheduleReconnect() }
            }
        }
        socket = s
        s.start()
    }

    private func handle(frame: [String: Any]) {
        guard let payload = frame["payload"] as? [String: Any] else { return }
        let kind = payload["type"] as? String ?? ""
        let sessionId = payload["sessionId"] as? String ?? ""
        switch kind {
        case "session/event":
            guard let event = payload["event"] as? [String: Any] else { return }
            if sessionId == selected {
                reduce(event: event)
            } else if event["type"] as? String == "session/title" {
                scheduleSessionsRefresh()
            }
        case "session/projection":
            guard sessionId == selected, let key = payload["key"] as? String else { return }
            let projectionValue = payload["value"] ?? [:]
            projectionSnapshots[sessionId, default: [:]][key] = projectionValue
            applyProjection(key: key, value: projectionValue)
        case "approval/requested":
            let request = ApprovalRequest(
                id: payload["approvalId"] as? String ?? UUID().uuidString,
                rpcId: frame["rpcId"] as? String ?? "",
                sessionId: sessionId,
                toolName: payload["toolName"] as? String ?? "tool",
                reason: payload["reason"] as? String,
                callId: payload["callId"] as? String
            )
            if !approvals.contains(request) {
                approvals.append(request)
            }
        case "approval/resolved":
            let approvalId = payload["approvalId"] as? String ?? ""
            approvals.removeAll { $0.id == approvalId }
        case "question/requested":
            let items = (payload["questions"] as? [[String: Any]] ?? []).compactMap { q -> QuestionItem? in
                guard let qid = q["id"] as? String, let text = q["question"] as? String else { return nil }
                let options = (q["options"] as? [[String: Any]] ?? []).compactMap { opt -> QuestionOption? in
                    guard let label = opt["label"] as? String else { return nil }
                    return QuestionOption(label: label, description: opt["description"] as? String)
                }
                return QuestionItem(
                    id: qid,
                    question: text,
                    header: q["header"] as? String,
                    detail: q["detail"] as? String,
                    options: options,
                    multiSelect: q["multiSelect"] as? Bool ?? false,
                    approveLabel: ((q["intent"] as? [String: Any])?["approve"]) as? String
                )
            }
            guard !items.isEmpty else { return }
            let request = QuestionRequest(rpcId: frame["rpcId"] as? String ?? "", sessionId: sessionId, items: items)
            if !questions.contains(where: { $0.rpcId == request.rpcId }) {
                questions.append(request)
            }
        case "question/resolved":
            let resolvedRpcId = payload["questionRpcId"] as? String
            questions.removeAll { $0.rpcId == resolvedRpcId }
        case "session/queue":
            guard sessionId == selected else { return }
            queueItems = (payload["items"] as? [[String: Any]] ?? []).compactMap { item in
                guard let itemId = item["id"] as? String else { return nil }
                let message = item["message"] as? [String: Any] ?? [:]
                let text = EventReducer.messageText(message) ?? EventReducer.messageText(["message": message]) ?? ""
                return QueueItem(
                    id: itemId,
                    placement: item["placement"] as? String ?? "queued",
                    text: String(text.prefix(120))
                )
            }
        case "session/jobs":
            guard sessionId == selected else { return }
            jobs = (payload["jobs"] as? [[String: Any]] ?? []).compactMap { job in
                guard let jobId = job["id"] as? String,
                      let label = job["label"] as? String else { return nil }
                return JobView(
                    id: jobId,
                    kind: job["kind"] as? String ?? "job",
                    label: label,
                    status: job["status"] as? String ?? "running",
                    detail: job["detail"] as? String
                )
            }
        default:
            break
        }
    }

    func skipQuestion(_ request: QuestionRequest) {
        questions.removeAll { $0.rpcId == request.rpcId }
        Task {
            do {
                try await client.cancel(rpcId: request.rpcId, reason: "the user skipped this question")
            } catch {
                report("skip failed: \(error.localizedDescription)")
            }
        }
    }

    // dsh validates the shape before it hands the answer to the agent: one entry
    // per question in the order asked, no duplicate labels, no blank custom
    // text, and for a single-answer question either a selection or custom text
    // but never both. Anything else comes back as bad-response.
    func answerQuestion(_ request: QuestionRequest, selections: [String: Set<String>], custom: [String: String]) {
        questions.removeAll { $0.rpcId == request.rpcId }
        Task {
            do {
                let answers: [[String: Any]] = request.items.map { item in
                    let typed = (custom[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    var picked = Array(selections[item.id] ?? []).filter { label in
                        item.options.contains { $0.label == label }
                    }
                    if !item.multiSelect {
                        if !typed.isEmpty { picked = [] }
                        if picked.count > 1 { picked = Array(picked.prefix(1)) }
                    }
                    var answer: [String: Any] = ["id": item.id, "selected": picked]
                    if !typed.isEmpty {
                        answer["custom"] = typed
                    }
                    return answer
                }
                try await client.respond(rpcId: request.rpcId, value: [
                    "sessionId": request.sessionId,
                    "answer": ["answers": answers],
                ])
            } catch {
                report("answer failed: \(error.localizedDescription)")
            }
        }
    }

    private func reduce(event: [String: Any], live: Bool = true) {
        let type = event["type"] as? String ?? ""
        let data = event["data"] as? [String: Any] ?? [:]
        let id = "\(type)-\(event["seq"] ?? UUID().uuidString)"
        switch type {
        case "assistant/chunk":
            guard live, let chunk = data["chunk"] as? [String: Any] else { break }
            switch chunk["type"] as? String {
            case "text-delta":
                streamState.text += chunk["text"] as? String ?? ""
            case "reasoning-delta":
                streamState.thinking += chunk["text"] as? String ?? ""
            case "finish":
                streamState.clear()
            default:
                break
            }
        case "user/message":
            let text = EventReducer.messageText(data)
            let images = EventReducer.imageAttachmentIds(data)
            guard text != nil || !images.isEmpty else { return }
            if EventReducer.sourceKind(data) == "user" {
                appendItem(.user(id: id, text: text ?? "", images: images))
            } else if let text {
                appendItem(.context(id: id, summary: String(text.prefix(160))))
            }
        case "assistant/message":
            if live {
                streamState.clear()
            }
            if let thinking = EventReducer.reasoningText(data) {
                appendItem(.thinking(id: id + "-thinking", text: thinking))
            }
            if let text = EventReducer.messageText(data) {
                appendItem(.assistant(id: id, text: text))
            }
        case "turn/start":
            running = true
            if live { lastError = nil }
        case "turn/end":
            running = false
            // A turn that dies on a bad credential or a provider error ends the
            // same way a finished one does. Without this the send just goes
            // quiet and the prompt looks like it was never delivered.
            if live, let reason = data["reason"] as? [String: Any],
               reason["kind"] as? String == "error" {
                let error = reason["error"] as? [String: Any]
                report(error?["message"] as? String ?? "the turn ended with an error")
            }
            if live { refreshSubagents() }
        case "session/title":
            if live { scheduleSessionsRefresh() }
        case "tool/call":
            let callId = data["callId"] as? String ?? id
            let name = data["name"] as? String ?? "tool"
            var title = name
            var detail = ""
            var parsedArgs: [String: Any]?
            if let argsStr = data["arguments"] as? String,
               let argsData = argsStr.data(using: .utf8) {
                parsedArgs = (try? JSONSerialization.jsonObject(with: argsData)) as? [String: Any]
            } else if let dict = data["arguments"] as? [String: Any] {
                parsedArgs = dict
            }
            if let args = parsedArgs {
                if let d = args["description"] as? String { title = d }
                detail = args["code"] as? String ?? EventReducer.compact(args, limit: 800)
            }
            appendItem(.tool(id: callId, name: name, title: title, detail: detail, status: .running))
        case "tool/code-dispatch-start":
            let subId = data["subCallId"] as? String ?? id
            let name = data["name"] as? String ?? "sub-call"
            let args = data["arguments"] as? [String: Any] ?? [:]
            let hint = (args["file_path"] as? String).map(EventReducer.shortTail)
                ?? (args["command"] as? String)
                ?? (args["path"] as? String).map(EventReducer.shortTail)
                ?? ""
            appendItem(.tool(
                id: subId,
                name: name,
                title: hint.isEmpty ? name : hint,
                detail: EventReducer.compact(args, limit: 500),
                status: .running
            ))
        case "tool/code-dispatch":
            let subId = data["subCallId"] as? String ?? ""
            let isError = data["isError"] as? Bool ?? false
            let result = EventReducer.blockText(data["content"] as? [[String: Any]])
            updateTool(id: subId, status: isError ? .error : .ok, appending: result)
        case "tool/result":
            let blocks = (data["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            for block in blocks where block["type"] as? String == "tool-result" {
                guard let callId = block["toolCallId"] as? String else { continue }
                let isError = block["isError"] as? Bool ?? false
                let result = EventReducer.blockText(block["content"] as? [[String: Any]])
                updateTool(id: callId, status: isError ? .error : .ok, appending: result)
            }
        default:
            break
        }
    }

    private func appendItem(_ item: TrajectoryItem) {
        guard appendedIDs.insert(item.id).inserted else { return }
        items.append(item)
        if case .tool = item { toolIndex[item.id] = items.count - 1 }
    }

    private func updateTool(id: String, status: ToolStatus, appending: String) {
        guard let idx = toolIndex[id], idx < items.count,
              case .tool(let tid, let name, let title, let detail, _) = items[idx], tid == id else { return }
        let merged = appending.isEmpty ? detail : detail + "\n\n" + appending
        items[idx] = .tool(id: tid, name: name, title: title, detail: String(merged.prefix(4000)), status: status)
    }

    private func applyProjection(key: String, value: Any) {
        switch key {
        case "tokenUsage":
            guard let usage = value as? [String: Any] else { return }
            stats.uncachedInput = usage["uncachedInputTokens"] as? Int ?? stats.uncachedInput
            stats.output = usage["outputTokens"] as? Int ?? stats.output
            stats.cacheRead = usage["cacheReadTokens"] as? Int ?? stats.cacheRead
            stats.cacheWrite = usage["cacheWriteTokens"] as? Int ?? stats.cacheWrite
        case "sessionStats":
            guard let s = value as? [String: Any] else { return }
            stats.turns = s["turns"] as? Int ?? stats.turns
            stats.steps = s["steps"] as? Int ?? stats.steps
            stats.llmMs = s["llmMs"] as? Int ?? stats.llmMs
            stats.toolMs = s["toolMs"] as? Int ?? stats.toolMs
        case "contextPressure":
            guard let p = value as? [String: Any] else { return }
            let tokens = p["projectedTokens"] as? Int ?? p["pressureTokens"] as? Int
            if let tokens, let window = p["contextWindow"] as? Int, window > 0 {
                contextPressure = ContextPressure(tokens: tokens, window: window)
            }
        case "permissions":
            guard let p = value as? [String: Any],
                  let current = p["currentValue"] as? String else { return }
            let options = (p["options"] as? [[String: Any]] ?? []).compactMap { $0["value"] as? String }
            permission = PermissionSelect(options: options, current: current)
        case "goal":
            guard let wrapper = value as? [String: Any],
                  let g = wrapper["goal"] as? [String: Any],
                  let goalId = g["id"] as? String,
                  let objective = g["objective"] as? String else {
                goal = nil
                return
            }
            goal = GoalState(
                id: goalId,
                revision: g["revision"] as? Int ?? 1,
                objective: objective,
                phase: g["phase"] as? String ?? "active",
                blockedMessage: (g["blockedReason"] as? [String: Any])?["message"] as? String,
                maxRounds: g["maxGoalRounds"] as? Int ?? 0,
                roundsStarted: wrapper["roundsStarted"] as? Int ?? 0
            )
        default:
            break
        }
    }

    private func scheduleReconnect() {
        guard serverState == .ready, !reconnectInFlight else { return }
        reconnectInFlight = true
        Task { @MainActor in
            serverState = .connecting
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await connect()
            reconnectInFlight = false
        }
    }

    func retryConnect() {
        Task { await connect() }
    }

    // A failure belongs to the moment it happened, so it fades on its own and
    // whenever the session moves on. Otherwise it outlives its context and
    // reads as a fault in whatever the user is doing now.
    private func report(_ message: String) {
        lastError = message
        errorGeneration += 1
        let generation = errorGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if generation == errorGeneration { lastError = nil }
        }
    }
}
