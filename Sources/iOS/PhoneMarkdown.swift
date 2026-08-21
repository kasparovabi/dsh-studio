import SwiftUI

struct PhoneMarkdown: View {
    let text: String
    var tint: Color = .phoneInk

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(MarkdownParser.blocks(text)) { block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .code(_, let code, let language):
            PhoneCodeBlock(code: code, language: language)
        case .heading(_, let level, let text):
            Text(MarkdownParser.inline(text))
                .font(.system(size: level == 1 ? 17 : 15, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(_, let text):
            prose(text)
        case .bullet(_, let depth, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.system(size: 15, weight: marker == "•" ? .bold : .regular))
                    .foregroundStyle(tint.opacity(0.6))
                    .frame(minWidth: marker == "•" ? 6 : 18, alignment: .trailing)
                prose(text)
            }
            .padding(.leading, CGFloat(depth) * 14)
        case .quote(_, let text):
            HStack(alignment: .top, spacing: 10) {
                Capsule().fill(tint.opacity(0.25)).frame(width: 3)
                prose(text).foregroundStyle(tint.opacity(0.75))
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Rectangle()
                .fill(tint.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 2)
        case .table(_, let header, let rows):
            PhoneTable(header: header, rows: rows, tint: tint)
        }
    }

    private func prose(_ text: String) -> some View {
        Text(MarkdownParser.inline(text))
            .font(.system(size: 15))
            .lineSpacing(2.5)
            .foregroundStyle(tint)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PhoneCodeBlock: View {
    let code: String
    let language: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.07))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(white: 0.92))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.phoneSlate)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PhoneTable: View {
    let header: [String]
    let rows: [[String]]
    let tint: Color

    private var columnCount: Int { max(header.count, rows.map(\.count).max() ?? 0) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                row(header, bold: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                    Rectangle().fill(tint.opacity(0.1)).frame(height: 1)
                    row(cells, bold: false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.04))
            )
        }
    }

    private func row(_ cells: [String], bold: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { column in
                Text(column < cells.count ? cells[column] : "")
                    .font(.system(size: 13, weight: bold ? .semibold : .regular))
                    .foregroundStyle(bold ? tint : tint.opacity(0.75))
                    .frame(minWidth: 90, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
        }
    }
}
