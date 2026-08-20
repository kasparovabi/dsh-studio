import SwiftUI

struct TrajectoryView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
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
                    StreamingRows(stream: app.streamState, proxy: proxy)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.88),
                        .init(color: .black.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: app.items.count) {
                if let last = app.items.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card(radius: 18)
    }

    struct StreamingRows: View {
        @ObservedObject var stream: StreamState
        let proxy: ScrollViewProxy

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
                        Text(String(stream.thinking.suffix(300)))
                            .font(.system(size: 12))
                            .italic()
                            .foregroundStyle(Color.inkSecondary)
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
                        Text(String(stream.text.suffix(4000)) + " ▌")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.inkPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 20)
                    }
                    .id("streaming")
                }
            }
            .onChange(of: stream.text) {
                if !stream.text.isEmpty {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
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
            .background(Capsule().fill(Color.black.opacity(0.03)))
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
                    Text(title)
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
                        Text(detail)
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
                    Color.black.opacity(0.04)
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
