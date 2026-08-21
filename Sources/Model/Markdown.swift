import Foundation

enum MarkdownBlock: Identifiable {
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

enum MarkdownParser {
    private static var cache: [String: [MarkdownBlock]] = [:]
    private static var order: [String] = []

    static func blocks(_ text: String) -> [MarkdownBlock] {
        if let cached = cache[text] { return cached }
        let parsed = parse(text)
        cache[text] = parsed
        order.append(text)
        if order.count > 300 { cache.removeValue(forKey: order.removeFirst()) }
        return parsed
    }

    // AttributedString only reads inline syntax, so headings, lists, quotes and
    // tables would reach the screen as their own source text. Split the message
    // into blocks first and let each one carry its own shape.
    private static func parse(_ text: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var codeLanguage: String?
        var index = 0

        func nextId() -> Int {
            defer { index += 1 }
            return index
        }

        // A single Text taller than the window server's texture limit stops
        // drawing altogether, and an agent that answers with hundreds of
        // unbroken lines reaches that height. Cut long runs into several
        // paragraphs, which reads the same and keeps every layer in range.
        func flushParagraph() {
            let lines = paragraph
            paragraph = []
            for chunk in stride(from: 0, to: lines.count, by: 150) {
                let slice = lines[chunk..<min(chunk + 150, lines.count)]
                let body = slice.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { continue }
                result.append(.paragraph(id: nextId(), text: body))
            }
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

    static func inline(_ source: String) -> AttributedString {
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
