import SwiftUI

struct TrajectoryView: View {
    @EnvironmentObject var app: AppModel
    @State private var pinnedToBottom = true
    @State private var viewportFrame: CGRect = .zero
    @StateObject private var wheel = WheelMonitor()
    @State private var bottomGap = GapBox()

    final class GapBox {
        var value: CGFloat = 0
    }

    static let bottomAnchor = "trajectory-bottom"
    static let fadeBand: CGFloat = 46

    // How far the content can sit past the viewport before the transcript is
    // treated as parked rather than following.
    private static let pinThreshold: CGFloat = 60

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if app.items.isEmpty {
                            emptyState
                        }
                        ForEach(app.items) { item in
                            TrajectoryRow(item: item)
                                .id(item.id)
                        }
                        StreamingRows(stream: app.streamState, proxy: proxy, pinned: $pinnedToBottom)
                        // The card fades its bottom edge, so the anchor reserves
                        // that band. Without it a scroll that lands perfectly
                        // still leaves the newest line dissolving into the
                        // gradient.
                        Color.clear
                            .frame(height: Self.fadeBand)
                            .id(Self.bottomAnchor)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        GeometryReader { content in
                            // The gap lands in a plain box rather than in
                            // state. Republishing it on every streamed delta
                            // re-entered layout often enough that the whole
                            // pane stopped drawing.
                            Color.clear.onChange(
                                of: content.frame(in: .named("trajectory")).maxY - viewport.size.height
                            ) { _, gap in
                                bottomGap.value = gap
                            }
                        }
                    )
                }
                .coordinateSpace(name: "trajectory")
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.95),
                            .init(color: .black.opacity(0), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: app.items.count) {
                    guard pinnedToBottom else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    }
                    DispatchQueue.main.async {
                        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    }
                }
                .onChange(of: app.selected) {
                    jumpToBottom(proxy)
                }
                // The selection changes before the backlog is fetched, so its
                // jump lands in an empty stack. This one fires once the history
                // is in, which is when there is finally something to sit at the
                // bottom of.
                .onChange(of: app.historyRevision) {
                    jumpToBottom(proxy)
                }
                // Sending is a deliberate move to the end of the conversation,
                // so it takes the reader back down even while parked.
                .onChange(of: app.scrollPin) {
                    jumpToBottom(proxy)
                }
                .onChange(of: viewport.size) {
                    viewportFrame = viewport.frame(in: .global)
                }
                .onAppear {
                    viewportFrame = viewport.frame(in: .global)
                    jumpToBottom(proxy)
                    installWheelMonitor()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card(radius: 18)
    }

    // Measuring the gap alone is not enough while text streams in. A delta
    // lands every few frames and the scroll it triggers runs before the new
    // geometry has propagated, so the reader gets dragged back down. Watching
    // the wheel unparks the transcript in the same event the reader scrolls.
    // Removing it in onDisappear would leave the transcript deaf, because
    // SwiftUI can call onAppear for the replacement view before onDisappear for
    // the old one. Owning it in a StateObject instead means the monitor lives
    // exactly as long as the view's own storage and its deinit takes it back.
    private func installWheelMonitor() {
        wheel.install { event in
            noteWheel(event)
            return event
        }
    }

    private func noteWheel(_ event: NSEvent) {
        guard event.scrollingDeltaY != 0, viewportFrame != .zero else { return }
        guard let content = event.window?.contentView else { return }
        let point = CGPoint(
            x: event.locationInWindow.x,
            y: content.bounds.height - event.locationInWindow.y
        )
        guard viewportFrame.contains(point) else { return }
        if event.scrollingDeltaY > 0 {
            pinnedToBottom = false
            return
        }
        // Only a scroll back down resumes the follow. Text piling up until it
        // reaches whoever scrolled away is not them coming back, so growth
        // alone must never re-pin. The gap is read once the scroll has landed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if bottomGap.value < Self.pinThreshold {
                pinnedToBottom = true
            }
        }
    }

    // A freshly loaded transcript lays out over several passes inside the lazy
    // stack, so one scroll lands halfway up. Repeat until the layout settles,
    // re-pinning each time so the jump between two transcripts of different
    // length does not read as the reader scrolling backwards.
    private func jumpToBottom(_ proxy: ScrollViewProxy) {
        pinnedToBottom = true
        // A tall backlog realises its rows over several layout passes, and a
        // scroll issued before the rows above the anchor have a measured height
        // lands in blank space past the end. Re-issuing across a longer ladder
        // lets each pass correct the estimate the previous one scrolled against.
        for delay in [0.0, 0.05, 0.2, 0.5, 0.8, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                pinnedToBottom = true
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    struct StreamingRows: View {
        // How much of a stream stays on screen while it is still arriving. The
        // finished turn replaces it with the whole text a moment later.
        static let window = 4000

        @ObservedObject var stream: StreamState
        let proxy: ScrollViewProxy
        @Binding var pinned: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                if !stream.thinking.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.accentPurple.opacity(0.08))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "brain")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.accentPurple.opacity(0.6))
                            )
                        // Reasoning used to be shown through a 300 character
                        // window, which held it to about four lines and slid
                        // the earlier thought out of sight while the model was
                        // still writing it. It runs like any other message now,
                        // in its own colour.
                        Text(String(stream.thinking.suffix(StreamingRows.window)))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentPurple)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 20)
                    }
                    .id("thinking")
                }
                if !stream.text.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.accentPurple.opacity(0.14))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.accentPurple)
                            )
                        Text(String(stream.text.suffix(StreamingRows.window)) + " ▌")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.inkPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 20)
                    }
                    .id("streaming")
                }
            }
            // A delta arrives before its line is laid out, so scrolling in the
            // same pass lands short of the new height. Chase it once the layout
            // has settled as well.
            .onChange(of: stream.text) { follow() }
            .onChange(of: stream.thinking) { follow() }
        }

        private func follow() {
            guard pinned else { return }
            proxy.scrollTo(TrajectoryView.bottomAnchor, anchor: .bottom)
            DispatchQueue.main.async {
                proxy.scrollTo(TrajectoryView.bottomAnchor, anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentPurple.opacity(0.5))
            Text("Into the unknown")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.inkPrimary)
            Text("Type a task and let the harness take it from there.")
                .font(.system(size: 12))
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

struct TrajectoryRow: View {
    @EnvironmentObject var app: AppModel
    let item: TrajectoryItem
    @State private var expanded = false

    var body: some View {
        switch item {
        case .user(_, let text, let images):
            HStack(alignment: .top, spacing: 10) {
                avatar(system: "person.fill", tint: .accentOrange)
                VStack(alignment: .leading, spacing: 8) {
                    if !images.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(images, id: \.self) { attachmentId in
                                AttachmentThumbnail(attachmentId: attachmentId)
                            }
                        }
                    }
                    if !text.isEmpty {
                        Text(text)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.inkPrimary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentOrange.opacity(0.08))
                )
                Spacer(minLength: 40)
            }
        case .thinking(_, let text):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentPurple.opacity(0.65))
                    Text("Thought process")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.inkSecondary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                    Spacer()
                }
                if expanded {
                    Text(text)
                        .font(.system(size: 12))
                        .italic()
                        .foregroundStyle(Color.inkSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentPurple.opacity(0.04))
            )
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }
        case .assistant(_, let text):
            HStack(alignment: .top, spacing: 10) {
                avatar(system: "wand.and.stars", tint: .accentPurple)
                AssistantMarkdown(text: text)
                Spacer(minLength: 20)
            }
        case .context(_, let summary):
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.inkSecondary)
                Text("Context added")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                if expanded {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(3)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.chipFill))
            .onTapGesture { expanded.toggle() }
        case .tool(let id, let name, let title, let detail, let status):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    statusIcon(status)
                    Text(name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentTeal)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentTeal.opacity(0.12)))
                    Text(title.sanitizedForDisplay)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.inkPrimary)
                        .lineLimit(1)
                    Spacer()
                    if !detail.isEmpty {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                if expanded, !detail.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(detail.sanitizedForDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.inkSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentTeal.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentTeal.opacity(0.14), lineWidth: 1)
            )
            .padding(.leading, id.contains(":code:") ? 30 : 0)
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }
        }
    }

    private func statusIcon(_ status: ToolStatus) -> some View {
        Group {
            switch status {
            case .running:
                ProgressView().controlSize(.mini)
            case .ok:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentGreen)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
            }
        }
        .frame(width: 14)
    }

    private func avatar(system: String, tint: Color) -> some View {
        Circle()
            .fill(tint.opacity(0.14))
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: system)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
            )
    }
}

struct AttachmentThumbnail: View {
    @EnvironmentObject var app: AppModel
    let attachmentId: String

    var body: some View {
        Group {
            if let image = app.attachmentImages[attachmentId] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.chipFill
                    ProgressView().controlSize(.small)
                }
                .onAppear { app.loadAttachment(attachmentId) }
            }
        }
        .frame(width: 120, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        )
    }
}


// AppKit hands back an opaque token that has to be given back, and a SwiftUI
// view's own lifetime is the only thing here that knows when that is.
final class WheelMonitor: ObservableObject {
    private var token: Any?

    func install(_ handler: @escaping (NSEvent) -> NSEvent?) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: handler)
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }
}
