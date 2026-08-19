import SwiftUI
import AppKit

struct AssistantMarkdown: View {
    let text: String

    private struct Segment: Identifiable {
        let id: Int
        let code: String?
        let language: String
        let body: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                if let code = segment.code {
                    CodeBlockView(code: code, language: segment.language)
                } else {
                    Text(inlineMarkdown(segment.body))
                        .font(.system(size: 13))
                        .lineSpacing(2.5)
                        .foregroundStyle(Color.inkPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private static var segmentCache: [String: [Segment]] = [:]
    private static var cacheOrder: [String] = []

    private var segments: [Segment] {
        if let cached = Self.segmentCache[text] { return cached }
        let parsed = Self.parse(text)
        Self.segmentCache[text] = parsed
        Self.cacheOrder.append(text)
        if Self.cacheOrder.count > 300 {
            let evicted = Self.cacheOrder.removeFirst()
            Self.segmentCache.removeValue(forKey: evicted)
        }
        return parsed
    }

    private static func parse(_ text: String) -> [Segment] {
        var result: [Segment] = []
        var buffer: [String] = []
        var codeLanguage: String?
        var index = 0
        func flushText() {
            let body = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                result.append(Segment(id: index, code: nil, language: "", body: body))
                index += 1
            }
            buffer = []
        }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let language = codeLanguage {
                    result.append(Segment(id: index, code: buffer.joined(separator: "\n"), language: language, body: ""))
                    index += 1
                    buffer = []
                    codeLanguage = nil
                } else {
                    flushText()
                    codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
            } else {
                buffer.append(line)
            }
        }
        if let language = codeLanguage {
            result.append(Segment(id: index, code: buffer.joined(separator: "\n"), language: language, body: ""))
        } else {
            flushText()
        }
        return result
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
