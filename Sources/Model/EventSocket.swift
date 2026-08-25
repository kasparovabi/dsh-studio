import Foundation

// URLSession calls back on its own queue while the app drives start() and stop()
// from the main actor, so every piece of mutable state here sits behind one lock
// rather than being shared raw across the two.
final class EventSocket: NSObject, URLSessionWebSocketDelegate {
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pinger: DispatchSourceTimer?
    private var lastHeard = Date()
    private var closed = false
    private var reported = false

    private let url: URL
    private let accessToken: String
    private let onFrame: ([String: Any]) -> Void
    private let onState: (Bool, String?) -> Void

    // A dead tailnet link does not report itself: the socket stays open and
    // simply never speaks again. A ping every 20 seconds and a silence budget
    // turn that into an ordinary drop the app can reconnect from.
    private let pingInterval: TimeInterval = 20
    private let silenceBudget: TimeInterval = 70

    init(
        url: URL,
        accessToken: String = "",
        onFrame: @escaping ([String: Any]) -> Void,
        onState: @escaping (Bool, String?) -> Void
    ) {
        self.url = url
        self.accessToken = accessToken
        self.onFrame = onFrame
        self.onState = onState
    }

    private var isLoopback: Bool {
        let host = url.host ?? ""
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    func start() {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if !isLoopback, !accessToken.isEmpty {
            request.setValue(accessToken, forHTTPHeaderField: "X-Dsh-Key")
        }
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        lock.lock()
        self.session = session
        self.task = task
        lastHeard = Date()
        lock.unlock()
        task.resume()
        startPinging()
        receive()
    }

    func stop() {
        lock.lock()
        guard !closed else { return lock.unlock() }
        closed = true
        let task = self.task
        let session = self.session
        let pinger = self.pinger
        self.task = nil
        self.session = nil
        self.pinger = nil
        lock.unlock()
        pinger?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }

    deinit {
        stop()
    }

    // Every path out of the socket lands here, so the session is always
    // invalidated and the app is told exactly once.
    private func drop(_ reason: String) {
        lock.lock()
        let alreadyReported = reported || closed
        reported = true
        lock.unlock()
        guard !alreadyReported else { return }
        stop()
        onState(false, reason)
    }

    private func startPinging() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let task = self.task
            let silence = Date().timeIntervalSince(self.lastHeard)
            let closed = self.closed
            self.lock.unlock()
            guard !closed, let task else { return }
            if silence > self.silenceBudget {
                return self.drop("the stream went quiet for \(Int(silence))s")
            }
            task.sendPing { error in
                if let error { self.drop("ping failed: \(error.localizedDescription)") }
            }
        }
        lock.lock()
        pinger = timer
        lock.unlock()
        timer.resume()
    }

    private func receive() {
        lock.lock()
        let task = self.task
        let closed = self.closed
        lock.unlock()
        guard !closed, let task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            self.lock.lock()
            let stopped = self.closed
            if !stopped { self.lastHeard = Date() }
            self.lock.unlock()
            guard !stopped else { return }
            switch result {
            case .failure(let error):
                self.drop(error.localizedDescription)
            case .success(let message):
                if case .string(let text) = message,
                   let data = text.data(using: .utf8),
                   let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    self.onFrame(object)
                }
                self.receive()
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol proto: String?
    ) {
        lock.lock()
        let closed = self.closed
        if !closed { lastHeard = Date() }
        lock.unlock()
        guard !closed else { return }
        onState(true, nil)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith code: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) }
        drop("the server closed the stream (\(code.rawValue)\(text.map { ", \($0)" } ?? ""))")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        drop(error?.localizedDescription ?? "the stream ended")
    }
}
