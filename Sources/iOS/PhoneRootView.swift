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
                Spacer()
                center
                Spacer()
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
            Text(app.sessions.isEmpty ? "No sessions yet" : (currentTitle ?? "Pick a session"))
                .font(.system(size: 15))
                .foregroundStyle(Color.phoneInkSoft)
        case .failed:
            PhoneConnectView().environmentObject(app)
        default:
            Text(app.serverStatusText)
                .font(.system(size: 15))
                .foregroundStyle(Color.phoneInkSoft)
        }
    }

    private var currentTitle: String? {
        app.sessions.first { $0.id == app.selected }?.title
    }
}

struct PhoneTopBar: View {
    @EnvironmentObject var app: AppModel
    @Binding var sessionsOpen: Bool
    @Binding var newOpen: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button { sessionsOpen = true } label: {
                CircleControl(system: "line.3.horizontal")
            }
            Spacer(minLength: 0)
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
            Spacer(minLength: 0)
            Button { newOpen = true } label: {
                CircleControl(system: "square.and.pencil")
            }
        }
        .padding(.horizontal, Phone.margin)
        .padding(.top, 4)
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
    @State private var phase: Double = 0

    private let bars: [CGFloat] = [0.35, 0.7, 1.0, 0.55, 0.85, 0.4, 0.75, 0.5, 0.9, 0.3]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(bars.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(active ? 0.9 : 0.45))
                    .frame(width: 2, height: height(index))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: phase)
        .onAppear { pulse() }
        .onChange(of: active) { pulse() }
    }

    private func height(_ index: Int) -> CGFloat {
        let base = bars[index]
        guard active else { return 16 * base * 0.5 }
        let wave = sin(phase + Double(index) * 0.7)
        return 16 * base * (0.55 + 0.45 * CGFloat(abs(wave)))
    }

    private func pulse() {
        guard active else { return }
        Task { @MainActor in
            while active {
                phase += 0.9
                try? await Task.sleep(nanoseconds: 320_000_000)
            }
        }
    }
}

struct PhoneComposer: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(.white)
                    .frame(width: Phone.control, height: Phone.control)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.black)
                    )
                TextField("", text: $app.composer, axis: .vertical)
                    .placeholder(when: app.composer.isEmpty) {
                        Text("Write a task")
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .lineLimit(1...6)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: Phone.control, height: Phone.control)
                    .overlay(
                        Image(systemName: app.running ? "stop.fill" : "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    )
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(label: "Steer", active: true)
                    Chip(label: "Queue", active: false)
                    Chip(label: "Preset", active: false)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Phone.radiusComposer, style: .continuous)
                .fill(Color.phoneSlate)
        )
        .padding(.horizontal, Phone.margin)
        .padding(.bottom, 6)
    }
}

struct Chip: View {
    let label: String
    let active: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
            Image(systemName: active ? "xmark" : "plus")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(active ? .white : Color.phoneInk)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(active ? Color.phoneBlue : Color.phoneControl))
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
