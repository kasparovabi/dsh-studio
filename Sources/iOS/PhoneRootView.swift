import SwiftUI

struct PhoneRootView: View {
    @EnvironmentObject var app: AppModel
    @State private var sessionsOpen = false
    @State private var newOpen = false

    var body: some View {
        ZStack {
            Color.phoneGround.ignoresSafeArea()
            VStack(spacing: 0) {
                PhoneTopBar(sessionsOpen: $sessionsOpen, newOpen: $newOpen)
                center
                if let approval = app.approvals.first(where: { $0.sessionId == app.selected }) {
                    PhoneApprovalCard(approval: approval)
                }
                if let question = app.question {
                    PhoneQuestionCard(request: question)
                }
                PhoneComposer()
            }
        }
        .sheet(isPresented: $sessionsOpen) {
            PhoneSessionsView().environmentObject(app)
        }
        .sheet(isPresented: $newOpen) {
            PhoneNewSessionView { cwd in
                newOpen = false
                Task { await app.createSession(cwd: cwd) }
            }
            .environmentObject(app)
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var center: some View {
        switch app.serverState {
        case .ready:
            PhoneTrajectoryView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            Spacer()
            PhoneConnectView().environmentObject(app)
            Spacer()
        default:
            Spacer()
            Text(app.serverStatusText)
                .font(.system(size: 15))
                .foregroundStyle(Color.phoneInkSoft)
            Spacer()
        }
    }
}

struct PhoneTopBar: View {
    @EnvironmentObject var app: AppModel
    @Binding var sessionsOpen: Bool
    @Binding var newOpen: Bool
    @State private var modelOpen = false

    var body: some View {
        HStack(spacing: 10) {
            Button { sessionsOpen = true } label: {
                CircleControl(system: "line.3.horizontal")
            }
            Spacer(minLength: 0)
            Button { modelOpen = true } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                    Waveform(active: app.running)
                        .frame(width: 46, height: 16)
                    Text(app.model.isEmpty ? "dsh" : shortModel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 8)
                .frame(height: Phone.control)
                .background(Capsule().fill(Color.phoneGreen))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button { newOpen = true } label: {
                CircleControl(system: "square.and.pencil")
            }
        }
        .padding(.horizontal, Phone.margin)
        .padding(.top, 4)
        .sheet(isPresented: $modelOpen) {
            PhoneChoiceSheet(
                title: "Model",
                rows: app.modelOptions.map {
                    PhoneChoice(
                        id: $0.id,
                        label: $0.modelName,
                        detail: $0.providerName,
                        on: $0.provider == app.provider && $0.model == app.model
                    )
                }
            ) { id in
                if let option = app.modelOptions.first(where: { $0.id == id }) { app.selectModel(option) }
                modelOpen = false
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var shortModel: String {
        let parts = app.model.split(separator: "-")
        guard parts.count > 1 else { return app.model }
        return parts.dropFirst().joined(separator: "-").uppercased()
    }
}

// The pill in the reference carries a voice trace. Here it carries the only
// thing worth a live trace on a phone, which is whether the agent is working.
struct Waveform: View {
    let active: Bool
    @State private var lifted = false

    private let bars: [CGFloat] = [0.35, 0.7, 1.0, 0.55, 0.85, 0.4, 0.75, 0.5, 0.9, 0.3]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(bars.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(active ? 0.9 : 0.4))
                    .frame(width: 2, height: 16 * bars[index] * (active && lifted ? 1 : 0.45))
                    .animation(beat(index), value: lifted)
                    .animation(.easeInOut(duration: 0.3), value: active)
            }
        }
        .onAppear { lifted = true }
    }

    private func beat(_ index: Int) -> Animation? {
        guard active else { return .easeInOut(duration: 0.25) }
        return .easeInOut(duration: 0.42)
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.06)
    }
}

struct PhoneComposer: View {
    @EnvironmentObject var app: AppModel
    @FocusState private var writing: Bool
    @State private var steering = true
    @State private var presetOpen = false
    @State private var modelOpen = false

    private var hasText: Bool {
        !app.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                Button { app.send(mode: steering ? "steer" : "queue") } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: Phone.control, height: Phone.control)
                        .overlay(
                            Image(systemName: hasText ? "arrow.up" : "waveform")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.black)
                        )
                }
                .disabled(!hasText && app.pendingImages.isEmpty)
                TextField("", text: $app.composer, axis: .vertical)
                    .placeholder(when: app.composer.isEmpty) {
                        Text("Write a task")
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .lineLimit(1...6)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .focused($writing)
                    .padding(.vertical, 9)
                Button { app.running ? app.cancel() : (writing = true) } label: {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: Phone.control, height: Phone.control)
                        .overlay(
                            Image(systemName: app.running ? "stop.fill" : "plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                        )
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(label: steering ? "Steer" : "Queue", active: steering) {
                        steering.toggle()
                    }
                    Chip(label: presetLabel, active: app.agentPreset != nil) {
                        presetOpen = true
                    }
                    Chip(label: modelLabel, active: false) { modelOpen = true }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Phone.radiusComposer, style: .continuous)
                .fill(Color.phoneSlate)
        )
        .padding(.horizontal, Phone.margin)
        .padding(.bottom, 6)
        .sheet(isPresented: $presetOpen) {
            PhoneChoiceSheet(
                title: "Agent preset",
                rows: app.presetOptions.map {
                    PhoneChoice(id: $0.id, label: $0.name, detail: $0.description, on: $0.id == app.agentPreset)
                }
            ) { id in
                if let option = app.presetOptions.first(where: { $0.id == id }) { app.selectPreset(option) }
                presetOpen = false
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $modelOpen) {
            PhoneChoiceSheet(
                title: "Model",
                rows: app.modelOptions.map {
                    PhoneChoice(
                        id: $0.id,
                        label: $0.modelName,
                        detail: $0.providerName,
                        on: $0.provider == app.provider && $0.model == app.model
                    )
                }
            ) { id in
                if let option = app.modelOptions.first(where: { $0.id == id }) { app.selectModel(option) }
                modelOpen = false
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var presetLabel: String {
        guard let id = app.agentPreset else { return "Preset" }
        return app.presetOptions.first { $0.id == id }?.name ?? id
    }

    private var modelLabel: String {
        app.model.isEmpty ? "Model" : app.model
    }
}

struct Chip: View {
    let label: String
    let active: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Image(systemName: active ? "xmark" : "plus")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(active ? .white : Color.phoneInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(active ? Color.phoneBlue : Color.phoneControl))
        }
        .buttonStyle(.plain)
    }
}

struct PhoneChoice: Identifiable {
    let id: String
    let label: String
    let detail: String?
    let on: Bool
}

struct PhoneChoiceSheet: View {
    let title: String
    let rows: [PhoneChoice]
    let pick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.phoneGround.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.phoneInk)
                    Spacer()
                    Button { dismiss() } label: { CircleControl(system: "xmark") }
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            Button { pick(row.id) } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.label)
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color.phoneInk)
                                        if let detail = row.detail, !detail.isEmpty {
                                            Text(detail)
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color.phoneInkSoft)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if row.on {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.phoneInk)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if row.id != rows.last?.id {
                                Divider().overlay(Color.phoneWash).padding(.leading, 16)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Phone.radiusCard, style: .continuous)
                            .fill(Color.phoneCard)
                    )
                }
            }
            .padding(.horizontal, Phone.margin)
            .padding(.vertical, 18)
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when show: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .leading) {
            if show { content() }
            self
        }
    }
}
