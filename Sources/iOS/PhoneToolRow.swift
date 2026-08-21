import SwiftUI

struct PhoneToolRow: View {
    let name: String
    let title: String
    let detail: String
    let status: ToolStatus
    let nested: Bool
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.phoneInk)
                        .lineLimit(1)
                    if !title.isEmpty {
                        Text(title.sanitizedForDisplay)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.phoneInkSoft)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                if !detail.isEmpty {
                    Image(systemName: open ? "chevron.up" : "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.phoneInkSoft)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.phoneCard))
                }
            }
            if open, !detail.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(detail.sanitizedForDisplay)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.phoneInkSoft)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Phone.radiusCard, style: .continuous)
                .fill(Color.phoneWash)
        )
        .padding(.leading, nested ? 22 : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !detail.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.18)) { open.toggle() }
        }
    }

    private var badge: some View {
        Circle()
            .fill(tint.opacity(0.16))
            .frame(width: 28, height: 28)
            .overlay(
                Group {
                    if status == .running {
                        ProgressView().controlSize(.mini).tint(tint)
                    } else {
                        Image(systemName: glyph)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }
            )
    }

    private var tint: Color {
        switch status {
        case .running: return Color.phoneStamp
        case .ok: return Color.phoneGreen
        case .error: return Color.phoneRed
        }
    }

    private var glyph: String {
        switch status {
        case .running: return "circle.dashed"
        case .ok: return "checkmark"
        case .error: return "exclamationmark"
        }
    }
}
