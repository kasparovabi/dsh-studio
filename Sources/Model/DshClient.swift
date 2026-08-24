import Foundation

enum DshError: LocalizedError {
    case rpc(String)
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .rpc(let m): return m
        case .protocolError(let m): return m
        }
    }
}

struct DshClient {
    var host: String = "127.0.0.1"
    var port: Int

    func call(_ method: String, _ payload: Any = [String: Any]()) async throws -> Any {
        guard let url = URL(string: "http://\(host):\(port)/api/\(method)") else {
            throw DshError.protocolError("invalid url for \(method)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "client-request",
            "rpcId": UUID().uuidString,
            "method": method,
            "payload": payload,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = obj["result"] as? [String: Any] else {
            throw DshError.protocolError(String(data: data, encoding: .utf8) ?? "unexpected response")
        }
        if (result["ok"] as? Bool) == true {
            return result["value"] ?? [String: Any]()
        }
        let err = result["error"] as? [String: Any]
        throw DshError.rpc((err?["message"] as? String) ?? "rpc error: \(method)")
    }

    func respond(rpcId: String, value: [String: Any]) async throws {
        try await send(rpcId: rpcId, result: ["ok": true, "value": value])
    }

    // A question the user declines is not an error to report but a documented
    // outcome: dsh accepts the refusal only as a failed response carrying this
    // exact code, and answers anything else with bad-response.
    func cancel(rpcId: String, reason: String) async throws {
        try await send(rpcId: rpcId, result: [
            "ok": false,
            "error": ["code": "cancelled", "message": reason],
        ])
    }

    private func send(rpcId: String, result: [String: Any]) async throws {
        guard let url = URL(string: "http://\(host):\(port)/api/respond") else {
            throw DshError.protocolError("invalid respond url")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "client-response",
            "rpcId": rpcId,
            "result": result,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              obj["accepted"] as? Bool == true else {
            throw DshError.protocolError(String(data: data, encoding: .utf8) ?? "respond rejected")
        }
    }
}
