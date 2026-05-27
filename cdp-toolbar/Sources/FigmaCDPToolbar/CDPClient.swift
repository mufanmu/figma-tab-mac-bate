import Foundation

final class CDPClient: @unchecked Sendable {
    private(set) var currentURL: String = ""
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var nextId = 1
    private var continuations: [Int: CheckedContinuation<Data?, Never>] = [:]
    private var isConnected = false
    private let queue = DispatchQueue(label: "cdp-client")

    func connect(to wsURL: String) async -> Bool {
        currentURL = wsURL
        let s = URLSession(configuration: .default)
        session = s
        guard let url = URL(string: wsURL) else { return false }
        task = s.webSocketTask(with: url)
        task?.resume()
        isConnected = true
        receiveLoop()
        return true
    }

    func disconnect() {
        queue.sync {
            isConnected = false
            let pending = continuations
            continuations.removeAll()
            for (_, cont) in pending { cont.resume(returning: nil) }
        }
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session = nil
    }

    func send(_ method: String, params: [String: Any]? = nil) async -> String? {
        let id = queue.sync {
            let id = nextId
            nextId += 1
            return id
        }

        var msg: [String: Any] = ["id": id, "method": method]
        if let p = params { msg["params"] = p }

        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let text = String(data: data, encoding: .utf8) else {
            NSLog("[CDP] Failed to encode \(method)")
            return nil
        }

        let msgLen = text.count
        let raw: Data? = await withCheckedContinuation { cont in
            queue.sync { continuations[id] = cont }
            task?.send(.string(text)) { error in
                if let err = error {
                    NSLog("[CDP] Send FAIL id=\(id) \(method): \(err)")
                    self.queue.sync {
                        self.continuations[id]?.resume(returning: nil)
                        self.continuations.removeValue(forKey: id)
                    }
                }
            }
        }

        guard let raw = raw else {
            NSLog("[CDP] No response for id=\(id) \(method)")
            return nil
        }
        NSLog("[CDP] Got response for id=\(id) \(method) size=\(raw.count)")

        let json = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
        guard let json = json else {
            NSLog("[CDP] Cannot parse response for id=\(id)")
            return nil
        }

        if let err = json["error"] as? [String: Any] {
            NSLog("[CDP] Server error for id=\(id): \(err)")
            return nil
        }
        if let outerResult = json["result"] as? [String: Any],
           let result = outerResult["result"] as? [String: Any] {
            if let v = result["value"] as? String { return v }
            if let v = result["value"] as? NSNumber {
                if v === kCFBooleanTrue { return "true" }
                if v === kCFBooleanFalse { return "false" }
                return v.stringValue
            }
            if let d = result["description"] as? String { return d }
            if let v = result["value"] {
                let jd = try? JSONSerialization.data(withJSONObject: v, options: .fragmentsAllowed)
                if let jd, let js = String(data: jd, encoding: .utf8) { return js }
                return "\(v)"
            }
        }
        if let ex = json["exceptionDetails"] as? [String: Any] {
            return "ERROR: \(ex)"
        }
        NSLog("[CDP] Unknown response format for id=\(id): \(String(data: raw, encoding: .utf8)?.prefix(300) ?? "?")")
        return nil
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                let rawData: Data
                switch message {
                case .string(let t): rawData = Data(t.utf8)
                case .data(let d): rawData = d
                @unknown default: rawData = Data()
                }
                if let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
                   let id = json["id"] as? Int {
                    self.queue.sync {
                        if let cont = self.continuations[id] {
                            cont.resume(returning: rawData)
                            self.continuations.removeValue(forKey: id)
                        }
                    }
                }
                if self.isConnected { self.receiveLoop() }
            case .failure(let error):
                NSLog("[CDP] Receive error: \(error)")
                self.isConnected = false
            }
        }
    }
}
