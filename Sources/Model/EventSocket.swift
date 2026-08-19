import Foundation

final class EventSocket: NSObject, URLSessionWebSocketDelegate {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private let url: URL
    private let onFrame: ([String: Any]) -> Void
    private let onState: (Bool) -> Void
    private var closed = false

    init(url: URL, onFrame: @escaping ([String: Any]) -> Void, onState: @escaping (Bool) -> Void) {
        self.url = url
        self.onFrame = onFrame
        self.onState = onState
    }

    func start() {
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session = s
        let t = s.webSocketTask(with: url)
        task = t
        t.resume()
        receive()
    }

    func stop() {
        closed = true
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self, !self.closed else { return }
            switch result {
            case .failure:
                self.onState(false)
            case .success(let msg):
                if case .string(let text) = msg,
                   let data = text.data(using: .utf8),
                   let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    self.onFrame(obj)
                }
                self.receive()
            }
        }
    }

    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol proto: String?) {
        guard !closed else { return }
        onState(true)
    }

    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard !closed else { return }
        onState(false)
    }
}
