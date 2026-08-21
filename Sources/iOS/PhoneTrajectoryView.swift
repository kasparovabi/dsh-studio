import SwiftUI

final class GapBox {
    var value: CGFloat = 0
}

struct PhoneTrajectoryView: View {
    @EnvironmentObject var app: AppModel
    @State private var pinned = true
    @State private var gap = GapBox()
    @State private var viewportHeight: CGFloat = 0

    static let bottomAnchor = "phone-trajectory-bottom"
    private static let space = "phone-trajectory"
    private static let pinThreshold: CGFloat = 60

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let stamp = dateStamp {
                            Text(stamp)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.phoneStamp)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 6)
                        }
                        ForEach(app.items) { item in
                            PhoneTrajectoryRow(item: item)
                                .transition(.opacity.combined(with: .offset(y: 8)))
                        }
                        PhoneStreamingRows(stream: app.streamState, running: app.running) {
                            follow(proxy)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchor)
                            .background(
                                GeometryReader { tail in
                                    // The distance to the bottom lives in a plain
                                    // box. Publishing it on every streamed delta
                                    // would re-enter layout while the text grows.
                                    Color.clear.onChange(
                                        of: tail.frame(in: .named(Self.space)).maxY
                                    ) { _, maxY in
                                        gap.value = maxY - viewportHeight
                                    }
                                }
                            )
                    }
                    .padding(.horizontal, Phone.margin)
                    .padding(.bottom, 16)
                }
                .coordinateSpace(name: Self.space)
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.height > 10 { pinned = false }
                        }
                        .onEnded { _ in
                            if gap.value < Self.pinThreshold { pinned = true }
                        }
                )
                .onChange(of: app.items.count) { follow(proxy) }
                .onChange(of: app.selected) { jump(proxy) }
                .onChange(of: app.scrollPin) { jump(proxy) }
                .onAppear {
                    viewportHeight = viewport.size.height
                    jump(proxy)
                }
                .onChange(of: viewport.size) { viewportHeight = viewport.size.height }
            }
        }
        .overlay {
            if app.items.isEmpty && app.streamState.text.isEmpty && !app.running {
                Text("Nothing here yet")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.phoneInkSoft)
            }
        }
    }

    private func follow(_ proxy: ScrollViewProxy) {
        guard pinned else { return }
        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        DispatchQueue.main.async { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
    }

    private func jump(_ proxy: ScrollViewProxy) {
        pinned = true
        for delay in [0.0, 0.05, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    private var dateStamp: String? {
        guard let row = app.sessions.first(where: { $0.id == app.selected }), row.updatedAt > 0 else {
            return nil
        }
        let date = Date(timeIntervalSince1970: row.updatedAt / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'Today', HH:mm" : "d MMM, HH:mm"
        return formatter.string(from: date)
    }
}

struct PhoneStreamingRows: View {
    @ObservedObject var stream: StreamState
    let running: Bool
    let follow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !stream.thinking.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.phoneStamp)
                        .padding(.top, 3)
                    Text(String(stream.thinking.suffix(400)))
                        .font(.system(size: 13))
                        .italic()
                        .foregroundStyle(Color.phoneInkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !stream.text.isEmpty {
                Text(String(stream.text.suffix(4000)))
                    .font(.system(size: 15))
                    .lineSpacing(2.5)
                    .foregroundStyle(Color.phoneInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if running && stream.text.isEmpty {
                PhoneGeneratingRow()
            }
        }
        .onChange(of: stream.text) { follow() }
        .onChange(of: stream.thinking) { follow() }
    }
}

struct PhoneGeneratingRow: View {
    @State private var lifted = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.phoneInkSoft)
                        .frame(width: 6, height: 6)
                        .opacity(lifted ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.16),
                            value: lifted
                        )
                }
            }
            Text("Generating")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.phoneStamp)
        }
        .onAppear { lifted = true }
    }
}

struct PhoneTrajectoryRow: View {
    @EnvironmentObject var app: AppModel
    let item: TrajectoryItem

    var body: some View {
        switch item {
        case .user(_, let text, let images):
            PhoneUserBubble(text: text, images: images)
        case .assistant(_, let text):
            PhoneMarkdown(text: text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .thinking(_, let text):
            PhoneThinkingBlock(text: text)
        case .context(_, let summary):
            PhoneNoteRow(icon: "arrow.triangle.2.circlepath", text: summary)
        case .tool(let id, let name, let title, let detail, let status):
            PhoneToolRow(
                name: name,
                title: title,
                detail: detail,
                status: status,
                nested: id.contains(":code:")
            )
        }
    }
}

struct PhoneUserBubble: View {
    @EnvironmentObject var app: AppModel
    let text: String
    let images: [String]

    var body: some View {
        HStack {
            // The bubble stops at 78 percent of the screen, and the margins are
            // already inside this row, so the gutter carries the rest.
            Spacer(minLength: 56)
            HStack(alignment: .top, spacing: 8) {
                ForEach(images, id: \.self) { attachmentId in
                    if let image = app.attachmentImages[attachmentId] {
                        Image(platform: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                Text(text.sanitizedForDisplay)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: Phone.radiusBubble, style: .continuous)
                    .fill(Color.phoneSlate)
            )
        }
        .onAppear { images.forEach(app.loadAttachment) }
    }
}

struct PhoneThinkingBlock: View {
    let text: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Thinking")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Color.phoneStamp)
            }
            .buttonStyle(.plain)
            if open {
                Text(text.sanitizedForDisplay)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.phoneInkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Phone.radiusCard, style: .continuous)
                .fill(Color.phoneWash)
        )
    }
}

struct PhoneNoteRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.phoneInkSoft)
            Text(text.sanitizedForDisplay)
                .font(.system(size: 13))
                .foregroundStyle(Color.phoneInkSoft)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}
