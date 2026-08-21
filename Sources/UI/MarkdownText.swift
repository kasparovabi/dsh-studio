import SwiftUI
import AppKit

struct AssistantMarkdown: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MarkdownParser.blocks(text)) { block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .code(_, let code, let language):
            CodeBlockView(code: code, language: language)
        case .heading(_, let level, let text):
            Text(inlineMarkdown(text))
                .font(.system(size: headingSize(level), weight: level == 1 ? .bold : .semibold))
                .foregroundStyle(Color.inkPrimary)
                .textSelection(.enabled)
                .padding(.top, level == 1 ? 6 : 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(_, let text):
            prose(text)
        case .bullet(_, let depth, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.system(size: 13, weight: marker == "•" ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(Color.inkSecondary)
                    .frame(minWidth: marker == "•" ? 6 : 16, alignment: .trailing)
                prose(text)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case .quote(_, let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentPurple.opacity(0.35))
                    .frame(width: 3)
                prose(text)
                    .foregroundStyle(Color.inkSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
                .padding(.vertical, 2)
        case .table(_, let header, let rows):
            TableBlock(header: header, rows: rows)
        }
    }

    private func prose(_ text: String) -> some View {
        Text(inlineMarkdown(text))
            .font(.system(size: 13))
            .lineSpacing(2.5)
            .foregroundStyle(Color.inkPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 17
        case 2: return 15
        default: return 13.5
        }
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        MarkdownParser.inline(source)
    }
}

struct TableBlock: View {
    let header: [String]
    let rows: [[String]]

    private var columnCount: Int {
        max(header.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(header, isHeader: true)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                Rectangle().fill(Color.hairline).frame(height: 1)
                row(cells, isHeader: false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        )
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { column in
                Text(cell(cells, column))
                    .font(.system(size: 12, weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(isHeader ? Color.inkPrimary : Color.inkSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                if column < columnCount - 1 {
                    Rectangle().fill(Color.hairline).frame(width: 1)
                }
            }
        }
    }

    private func cell(_ cells: [String], _ column: Int) -> String {
        column < cells.count ? cells[column] : ""
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.06))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xE8EAED))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.inkPrimary)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
