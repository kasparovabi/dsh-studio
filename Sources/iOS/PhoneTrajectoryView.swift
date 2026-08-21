import SwiftUI

struct PhoneTrajectoryView: View {
    @EnvironmentObject var app: AppModel

    static let bottomAnchor = "phone-trajectory-bottom"

    var body: some View {
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
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(.horizontal, Phone.margin)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: app.items.count) {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
            .onChange(of: app.selected) {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
        .overlay {
            if app.items.isEmpty {
                Text("Nothing here yet")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.phoneInkSoft)
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
        case .tool(_, _, let title, let detail, let status):
            PhoneNoteRow(icon: icon(status), text: title.isEmpty ? detail : title)
        }
    }

    private func icon(_ status: ToolStatus) -> String {
        switch status {
        case .running: return "circle.dashed"
        case .ok: return "checkmark.circle"
        case .error: return "exclamationmark.circle"
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
