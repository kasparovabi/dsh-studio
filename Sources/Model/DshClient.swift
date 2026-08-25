import Foundation

enum DshError: LocalizedError {
    // dsh answers a failed call with a discriminated union on `code`, and the
    // typed details that ride along name which session, which namespace, which
    // revision. Collapsing all of it into one string at the door means no caller
    // can ever act on the difference, so the shape is carried instead.
    case rpc(code: String, message: String, details: [String: Any], rpcId: String)
    case http(status: Int, rpcId: String)
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .rpc(_, let message, _, _): return message
        case .http(let status, _): return "the server answered \(status)"
        case .protocolError(let message): return message
        }
    }

    var code: String? {
        if case .rpc(let code, _, _, _) = self { return code }
        return nil
    }

    var details: [String: Any] {
        if case .rpc(_, _, let details, _) = self { return details }
        return [:]
    }

    // The id the server logged this exchange under. Without it a report on
    // screen cannot be lined up with a line in the server's own log.
    var rpcId: String? {
        switch self {
        case .rpc(_, _, _, let id), .http(_, let id): return id
        case .protocolError: return nil
        }
    }
}

struct DshClient {
    var host: String = "127.0.0.1"
    var port: Int
    // Reaching a server on another machine goes through the tailnet proxy, which
    // refuses anything that does not carry this key. A loopback server, which
    // has no proxy in front of it, never sees it.
    var accessToken: String = ""

    private var isLoopback: Bool {
        host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func request(path: String, timeout: TimeInterval) throws -> URLRequest {
        guard let url = URL(string: "http://\(host):\(port)/api/\(path)") else {
            throw DshError.protocolError("invalid url for \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !isLoopback, !accessToken.isEmpty {
            request.setValue(accessToken, forHTTPHeaderField: "X-Dsh-Key")
        }
        return request
    }

    // A body that is not the JSON envelope is either the proxy speaking for
    // itself or a server that has lost the plot. Either way it is untrusted text
    // of unknown length, so it is capped rather than handed onward whole.
    private func describe(_ data: Data, status: Int) -> String {
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return "the server answered \(status) with an empty body" }
        let clipped = text.count > 200 ? String(text.prefix(200)) + "…" : text
        return "the server answered \(status): \(clipped)"
    }

    private func checkStatus(_ response: URLResponse, data: Data, rpcId: String) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { throw DshError.protocolError("the tailnet proxy refused this key") }
            throw DshError.http(status: status, rpcId: rpcId)
        }
    }

    func call(_ method: String, _ payload: Any = [String: Any]()) async throws -> Any {
        let rpcId = UUID().uuidString
        var request = try request(path: method, timeout: 20)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "client-request",
            "rpcId": rpcId,
            "method": method,
            "payload": payload,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, data: data, rpcId: rpcId)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = object["result"] as? [String: Any] else {
            throw DshError.protocolError(describe(data, status: status))
        }
        if (result["ok"] as? Bool) == true {
            return result["value"] ?? [String: Any]()
        }
        let error = result["error"] as? [String: Any]
        throw DshError.rpc(
            code: error?["code"] as? String ?? "unknown",
            message: error?["message"] as? String ?? "rpc error: \(method)",
            details: error?["details"] as? [String: Any] ?? [:],
            rpcId: rpcId
        )
    }

    func respond(rpcId: String, value: [String: Any]) async throws {
        try await send(rpcId: rpcId, result: ["ok": true, "value": value])
    }

    // A question the user declines is not an error to report but a documented
    // outcome: dsh accepts the refusal only as a failed response carrying this
    // exact code, and its schema requires `details` on that branch too, so an
    // envelope without it comes back as bad-response and the turn stays stuck.
    func cancel(rpcId: String, reason: String) async throws {
        try await send(rpcId: rpcId, result: [
            "ok": false,
            "error": ["code": "cancelled", "message": reason, "details": [String: Any]()],
        ])
    }

    private func send(rpcId: String, result: [String: Any]) async throws {
        var request = try request(path: "respond", timeout: 15)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "client-response",
            "rpcId": rpcId,
            "result": result,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, data: data, rpcId: rpcId)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DshError.protocolError(describe(data, status: status))
        }
        guard object["accepted"] as? Bool == true else {
            throw DshError.protocolError(object["reason"] as? String ?? "the server rejected the response")
        }
    }
}
