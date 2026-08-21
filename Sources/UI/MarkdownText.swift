import SwiftUI
import AppKit

struct AssistantMarkdown: View {
    let text: String

    private enum Block: Identifiable {
        case heading(id: Int, level: Int, text: String)
        case paragraph(id: Int, text: String)
        case bullet(id: Int, depth: Int, marker: String, text: String)
        case quote(id: Int, text: String)
        case rule(id: Int)
        case table(id: Int, header: [String], rows: [[String]])
        case code(id: Int, code: String, language: String)

        var id: Int {
            switch self {
            case .heading(let id, _, _), .paragraph(let id, _), .bullet(let id, _, _, _),
                 .quote(let id, _), .rule(let id), .table(let id, _, _), .code(let id, _, _):
                return id
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
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

    private static var blockCache: [String: [Block]] = [:]
    private static var cacheOrder: [String] = []

    private var blocks: [Block] {
        if let cached = Self.blockCache[text] { return cached }
        let parsed = Self.parse(text)
        Self.blockCache[text] = parsed
        Self.cacheOrder.append(text)
        if Self.cacheOrder.count > 300 {
            let evicted = Self.cacheOrder.removeFirst()
            Self.blockCache.removeValue(forKey: evicted)
        }
        return parsed
    }

    // AttributedString only reads inline syntax, so headings, lists, quotes and
    // tables would reach the screen as their own source text. Split the message
    // into blocks first and let each one carry its own shape.
    private static func parse(_ text: String) -> [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var code: [String] = []
        var codeLanguage: String?
        var index = 0

        func nextId() -> Int {
            defer { index += 1 }
            return index
        }

        func flushParagraph() {
            let body = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph = []
            guard !body.isEmpty else { return }
            result.append(.paragraph(id: nextId(), text: body))
        }

        let lines = text.components(separatedBy: "\n")
        var cursor = 0
        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if let language = codeLanguage {
                    result.append(.code(id: nextId(), code: code.joined(separator: "\n"), language: language))
                    code = []
                    codeLanguage = nil
                } else {
                    flushParagraph()
                    codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                cursor += 1
                continue
            }
            if codeLanguage != nil {
                code.append(line)
                cursor += 1
                continue
            }
            if let heading = headingLevel(trimmed) {
                flushParagraph()
                let body = String(trimmed.dropFirst(heading)).trimmingCharacters(in: .whitespaces)
                result.append(.heading(id: nextId(), level: min(heading, 3), text: body))
                cursor += 1
                continue
            }
            if isRule(trimmed) {
                flushParagraph()
                result.append(.rule(id: nextId()))
                cursor += 1
                continue
            }
            if isTableRow(trimmed), cursor + 1 < lines.count,
               isTableDivider(lines[cursor + 1].trimmingCharacters(in: .whitespaces)) {
                flushParagraph()
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                cursor += 2
                while cursor < lines.count {
                    let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard isTableRow(candidate) else { break }
                    rows.append(tableCells(candidate))
                    cursor += 1
                }
                result.append(.table(id: nextId(), header: header, rows: rows))
                continue
            }
            if let (marker, body) = listItem(line) {
                flushParagraph()
                let depth = min(indentDepth(line), 3)
                result.append(.bullet(id: nextId(), depth: depth, marker: marker, text: body))
                cursor += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                result.append(.quote(id: nextId(), text: body))
                cursor += 1
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                cursor += 1
                continue
            }
            paragraph.append(line)
            cursor += 1
        }

        if codeLanguage != nil {
            result.append(.code(id: nextId(), code: code.joined(separator: "\n"), language: codeLanguage ?? ""))
        }
        flushParagraph()
        return result
    }

    private static func headingLevel(_ line: String) -> Int? {
        var hashes = 0
        for character in line {
            if character == "#" { hashes += 1 } else { break }
        }
        guard hashes > 0, hashes <= 6, line.count > hashes else { return nil }
        let after = line[line.index(line.startIndex, offsetBy: hashes)]
        return after == " " ? hashes + 1 : nil
    }

    private static func isRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        return line.allSatisfy { $0 == "-" } || line.allSatisfy { $0 == "*" } || line.allSatisfy { $0 == "_" }
    }

    private static func indentDepth(_ line: String) -> Int {
        let spaces = line.prefix { $0 == " " }.count
        let tabs = line.prefix { $0 == "\t" }.count
        return tabs > 0 ? tabs : spaces / 2
    }

    private static func listItem(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for bullet in ["- ", "* ", "+ "] where trimmed.hasPrefix(bullet) {
            let body = String(trimmed.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces)
            return body.isEmpty ? nil : ("•", body)
        }
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        let body = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        return body.isEmpty ? nil : ("\(digits).", body)
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.dropFirst().contains("|")
    }

    private static func isTableDivider(_ line: String) -> Bool {
        guard isTableRow(line) else { return false }
        let cells = tableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
        }
    }

    private static func tableCells(_ line: String) -> [String] {
        var body = line
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        return body.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        guard var attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return AttributedString(source) }
        for run in attributed.runs where run.link != nil {
            let scheme = run.link?.scheme?.lowercased()
            if scheme != "http" && scheme != "https" {
                attributed[run.range].link = nil
            }
        }
        return attributed
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
