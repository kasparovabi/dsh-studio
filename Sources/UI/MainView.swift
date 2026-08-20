import SwiftUI

struct MainView: View {
    @EnvironmentObject var app: AppModel

    private var activeJobs: [JobView] {
        app.jobs.filter { $0.status == "running" || $0.status == "stopping" }
    }

    var body: some View {
        VStack(spacing: 14) {
            if app.serverState != .ready {
                ServerBanner()
            }
            TopBar()
            if app.recoveredHistory {
                RecoveredBanner()
            }
            StatsRow()
            if let goal = app.goal {
                GoalCard(goal: goal)
            }
            if !activeJobs.isEmpty {
                JobsStrip(jobs: activeJobs)
            }
            if !app.subagents.isEmpty {
                SubagentStrip()
            }
            TrajectoryView()
            if let approval = app.approvals.first(where: { $0.sessionId == app.selected }) {
                ApprovalCard(approval: approval)
            }
            if let question = app.question, question.sessionId == app.selected {
                QuestionCard(request: question)
                    .id(question.rpcId)
            }
            ComposerView()
        }
    }
}

struct RecoveredBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentOrange)
            Text("Rebuilt from the session log on disk, because dsh refused to serve this history. Any record it could not parse was skipped.")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentOrange.opacity(0.10))
        )
    }
}

struct ServerBanner: View {
    @EnvironmentObject var app: AppModel

    private var failed: Bool {
        if case .failed = app.serverState { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 10) {
            if failed {
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.red.opacity(0.8))
            } else {
                ProgressView().controlSize(.small)
            }
            Text(app.serverStatusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.inkPrimary)
                .lineLimit(1)
            Spacer()
            if failed {
                Button {
                    app.retryConnect()
                } label: {
                    Text("Retry")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.inkPrimary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill((failed ? Color.red : Color.accentOrange).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke((failed ? Color.red : Color.accentOrange).opacity(0.2), lineWidth: 1)
        )
    }
}

struct SubagentStrip: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentPurple)
            Text("Subagents")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(app.subagents) { entry in
                        Button {
                            app.openSubagent(entry)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(entry.activity == "running" ? Color.accentGreen : Color.inkSecondary.opacity(0.4))
                                    .frame(width: 6, height: 6)
                                Text(entry.label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.inkPrimary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 240, alignment: .leading)
                                if entry.activity == "running", entry.mode == "continuable" {
                                    Image(systemName: "stop.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.red.opacity(0.7))
                                        .onTapGesture { app.interruptSubagent(entry) }
                                        .help("Interrupt subagent")
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.accentPurple.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .card(radius: 14)
        .sheet(item: $app.subagentSheet) { entry in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentPurple)
                    Text(entry.label)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Button("Close") { app.subagentSheet = nil }
                }
                Divider()
                if app.subagentHistory.isEmpty {
                    Text("No messages")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(app.subagentHistory.enumerated()), id: \.offset) { _, row in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.0 == "user" ? "Parent → subagent" : "Subagent")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(row.0 == "user" ? Color.accentOrange : Color.accentPurple)
                                    Text(row.1)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.inkPrimary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
            .frame(width: 520, height: 420)
        }
    }
}

struct JobsStrip: View {
    let jobs: [JobView]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentTeal)
            Text("Background jobs")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(jobs) { job in
                        HStack(spacing: 6) {
                            if job.status == "running" {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "stop.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.accentOrange)
                            }
                            Text(job.kind)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.accentTeal)
                            Text(job.label)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.inkPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: 260, alignment: .leading)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentTeal.opacity(0.08)))
                        .help(job.detail ?? job.label)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .card(radius: 14)
    }
}

struct GoalCard: View {
    @EnvironmentObject var app: AppModel
    let goal: GoalState

    private var phaseColor: Color {
        switch goal.phase {
        case "active": return .accentGreen
        case "paused": return .accentOrange
        case "blocked": return .red
        default: return .accentPurple
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentPurple)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Goal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                    Text(goal.phase.capitalized)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(phaseColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(phaseColor.opacity(0.12)))
                    if goal.maxRounds > 0 {
                        Text("round \(goal.roundsStarted)/\(goal.maxRounds)")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                Text(goal.objective)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(2)
                if let blocked = goal.blockedMessage {
                    Text(blocked)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.red.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer()
            if goal.phase == "active" {
                goalButton("Pause") { app.goalAction("pause") }
            } else if goal.phase == "paused" {
                goalButton("Resume") { app.goalAction("resume") }
            }
            if goal.phase != "complete" {
                goalButton("Complete") { app.goalAction("complete") }
            }
            Button {
                app.goalAction("clear")
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.black.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .help("Clear goal")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentPurple.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentPurple.opacity(0.16), lineWidth: 1)
        )
    }

    private func goalButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.inkPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }
}

struct ApprovalCard: View {
    @EnvironmentObject var app: AppModel
    let approval: ApprovalRequest

    private var approvalArguments: String? {
        guard let callId = approval.callId else { return nil }
        for item in app.items {
            if case .tool(let tid, _, _, let detail, _) = item, tid == callId {
                return detail.isEmpty ? nil : detail
            }
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 16))
                .foregroundStyle(Color.accentOrange)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Approval required")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                    Text(approval.toolName.sanitizedForDisplay)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentOrange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentOrange.opacity(0.12)))
                }
                if let reason = approval.reason, !reason.isEmpty {
                    Text(reason.sanitizedForDisplay)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                }
                if let args = approvalArguments, !args.isEmpty {
                    Text(args.sanitizedForDisplay)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(4)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            Button {
                app.respond(to: approval, outcome: "rejected")
            } label: {
                Text("Reject")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
            Button {
                app.respond(to: approval, outcome: "allowed-once")
            } label: {
                Text("Allow once")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.inkPrimary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentOrange.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentOrange.opacity(0.25), lineWidth: 1)
        )
    }
}

struct TopBar: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(currentTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
                Text(currentPath)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if app.running {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Running")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentOrange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.accentOrange.opacity(0.12)))
            }
            if let permission = app.permission {
                permissionMenu(permission)
            }
            if !app.presetOptions.isEmpty {
                presetMenu
            }
            Button {
                app.openSkills()
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .help("Available skills")
            if let option = app.currentModelOption, !option.efforts.isEmpty {
                effortMenu(option)
            }
            modelMenu
            Button {
                app.openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .card(radius: 16)
        .sheet(isPresented: $app.settingsOpen) {
            SettingsView()
        }
        .sheet(isPresented: $app.skillsSheetOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentPurple)
                    Text("Skills")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button("Close") { app.skillsSheetOpen = false }
                }
                Divider()
                if app.skills.isEmpty {
                    Text("No skills available in this session.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(app.skills) { skill in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(skill.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.inkPrimary)
                                    Text(skill.description)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.inkSecondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
            .frame(width: 480, height: 400)
        }
    }

    private func permissionMenu(_ permission: PermissionSelect) -> some View {
        Menu {
            ForEach(permission.options, id: \.self) { option in
                Button {
                    app.selectPermission(option)
                } label: {
                    if option == permission.current {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(permission.current == "danger-full-access" ? Color.red : Color.accentGreen)
                Text(permission.current)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.accentGreen.opacity(0.08)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Permission preset (sandbox + approval policy)")
    }

    private var presetMenu: some View {
        let currentId = app.agentPreset ?? app.presetOptions.first(where: { $0.isDefault })?.id
        let currentName = app.presetOptions.first(where: { $0.id == currentId })?.id ?? currentId ?? "preset"
        return Menu {
            ForEach(app.presetOptions) { option in
                Button {
                    app.selectPreset(option)
                } label: {
                    if option.id == currentId {
                        Label("\(option.id) — \(option.name)", systemImage: "checkmark")
                    } else {
                        Text("\(option.id) — \(option.name)")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentOrange)
                Text(currentName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.accentOrange.opacity(0.08)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Agent preset")
    }

    private func effortMenu(_ option: ModelOption) -> some View {
        let currentId = app.reasoningEffort ?? option.defaultEffort
        let currentName = option.efforts.first(where: { $0.id == currentId })?.name ?? currentId ?? "Auto"
        return Menu {
            ForEach(option.efforts) { effort in
                Button {
                    app.selectEffort(effort.id)
                } label: {
                    if effort.id == currentId {
                        Label(effort.name, systemImage: "checkmark")
                    } else {
                        Text(effort.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentTeal)
                Text(currentName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.accentTeal.opacity(0.10)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Reasoning effort")
    }

    private var currentSession: SessionRow? {
        app.sessions.first { $0.id == app.selected }
    }

    private var currentTitle: String {
        currentSession?.title ?? "No session selected"
    }

    private var currentPath: String {
        currentSession?.cwd ?? ""
    }

    private var modelMenu: some View {
        Menu {
            ForEach(groupedProviders, id: \.self) { providerName in
                Section(providerName) {
                    ForEach(app.modelOptions.filter { $0.providerName == providerName }) { option in
                        Button(option.modelName) {
                            app.selectModel(option)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Color.accentPurple).frame(width: 7, height: 7)
                Text(app.model.isEmpty ? "Model" : app.model)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.black.opacity(0.04)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var groupedProviders: [String] {
        var seen: [String] = []
        for option in app.modelOptions where !seen.contains(option.providerName) {
            seen.append(option.providerName)
        }
        return seen
    }
}

struct StatsRow: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(spacing: 14) {
            TokenCard()
            MetricsCard()
        }
        .frame(height: 62)
    }
}

struct TokenCard: View {
    @EnvironmentObject var app: AppModel

    private var segments: [(Color, Int, String)] {
        [
            (.accentOrange, app.stats.uncachedInput, "In"),
            (.accentPurple, app.stats.output, "Out"),
            (.accentTeal, app.stats.cacheRead, "Read"),
            (.accentGreen, app.stats.cacheWrite, "Write"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatCount(app.stats.totalTokens))
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.inkPrimary)
                    .fixedSize()
                Text("tokens")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize()
                Spacer(minLength: 10)
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    HStack(spacing: 4) {
                        Circle().fill(seg.0).frame(width: 6, height: 6)
                        Text(seg.2)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .fixedSize()
                    .help("\(seg.2): \(formatCount(seg.1)) tokens")
                }
                if let pressure = app.contextPressure {
                    HStack(spacing: 6) {
                        Text("Context")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.inkSecondary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.black.opacity(0.06))
                                Capsule()
                                    .fill(pressureColor(pressure.fraction))
                                    .frame(width: max(geo.size.width * pressure.fraction, 3))
                            }
                        }
                        .frame(width: 48, height: 5)
                        Text("\(Int(pressure.fraction * 100))%")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(pressureColor(pressure.fraction))
                    }
                    .fixedSize()
                    .padding(.leading, 4)
                    .help("\(formatCount(pressure.tokens)) of \(formatCount(pressure.window)) context tokens")
                }
            }
            .lineLimit(1)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    let total = max(app.stats.totalTokens, 1)
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        if seg.1 > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(seg.0)
                                .frame(width: max(geo.size.width * CGFloat(seg.1) / CGFloat(total) - 2, 3))
                        }
                    }
                    if app.stats.totalTokens == 0 {
                        RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.05))
                    }
                }
            }
            .frame(height: 9)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(radius: 16)
    }
}

struct MetricsCard: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(spacing: 0) {
            metric("Turns", "\(app.stats.turns)")
            divider
            metric("Steps", "\(app.stats.steps)")
            divider
            metric("Model time", formatMs(app.stats.llmMs))
            divider
            metric("Tool time", formatMs(app.stats.toolMs))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card(radius: 16)
    }

    private var divider: some View {
        Rectangle().fill(Color.hairline).frame(width: 1, height: 26)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.inkPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

func pressureColor(_ fraction: Double) -> Color {
    switch fraction {
    case ..<0.6: return .accentGreen
    case ..<0.85: return .accentOrange
    default: return .red
    }
}

func formatCount(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
    case 1_000...: return String(format: "%.1fK", Double(n) / 1_000)
    default: return "\(n)"
    }
}

func formatMs(_ ms: Int) -> String {
    switch ms {
    case 60_000...: return String(format: "%.1fm", Double(ms) / 60_000)
    case 1_000...: return String(format: "%.1fs", Double(ms) / 1_000)
    default: return "\(ms)ms"
    }
}
