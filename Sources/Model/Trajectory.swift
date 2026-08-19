import Foundation

enum ToolStatus {
    case running, ok, error
}

enum TrajectoryItem: Identifiable {
    case user(id: String, text: String, images: [String])
    case assistant(id: String, text: String)
    case thinking(id: String, text: String)
    case context(id: String, summary: String)
    case tool(id: String, name: String, title: String, detail: String, status: ToolStatus)

    var id: String {
        switch self {
        case .user(let id, _, _):
            return id
        case .assistant(let id, _), .thinking(let id, _), .context(let id, _):
            return id
        case .tool(let id, _, _, _, _):
            return id
        }
    }
}

struct SessionStats {
    var turns = 0
    var steps = 0
    var llmMs = 0
    var toolMs = 0
    var uncachedInput = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0

    var totalTokens: Int { uncachedInput + output + cacheRead + cacheWrite }
}

enum EventReducer {
    static func messageText(_ data: [String: Any]) -> String? {
        let content = (data["message"] as? [String: Any])?["content"] as? [[String: Any]]
            ?? data["content"] as? [[String: Any]]
        guard let blocks = content else { return nil }
        let text = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    static func reasoningText(_ data: [String: Any]) -> String? {
        let content = (data["message"] as? [String: Any])?["content"] as? [[String: Any]]
            ?? data["content"] as? [[String: Any]]
        let text = (content ?? []).compactMap { block -> String? in
            guard block["type"] as? String == "reasoning" else { return nil }
            return block["text"] as? String
        }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    static func imageAttachmentIds(_ data: [String: Any]) -> [String] {
        let content = (data["message"] as? [String: Any])?["content"] as? [[String: Any]]
            ?? data["content"] as? [[String: Any]]
        return (content ?? []).compactMap { block in
            guard block["type"] as? String == "image",
                  let attachment = block["attachment"] as? [String: Any] else { return nil }
            return attachment["attachmentId"] as? String
        }
    }

    static func sourceKind(_ data: [String: Any]) -> String {
        let source = (data["message"] as? [String: Any])?["source"] as? [String: Any]
            ?? data["source"] as? [String: Any]
        return source?["kind"] as? String ?? "user"
    }

    static func compact(_ value: Any, limit: Int = 220) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    static func blockText(_ blocks: [[String: Any]]?) -> String {
        (blocks ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    static func shortTail(_ path: String) -> String {
        path.split(separator: "/").suffix(2).joined(separator: "/")
    }
}
