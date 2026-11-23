import Foundation

/// Kết nối WebSocket ticks của Trader API:
/// `wss://{access_point}/v1/server-events/accounts/{id}/ws/ticks`.
/// Tự đăng ký lại mã, tự kết nối lại khi rớt mạng (exponential backoff).
@MainActor
final class TickStream {
    enum Status: Equatable {
        case idle
        case connecting
        case live
        case reconnecting
        case failed(String)

        var title: String {
            switch self {
            case .idle: return "Chưa kết nối"
            case .connecting: return "Đang kết nối…"
            case .live: return "Trực tiếp"
            case .reconnecting: return "Kết nối lại…"
            case .failed(let message): return message
            }
        }

        var isActive: Bool {
            if case .live = self { return true }
            return false
        }
    }

    private var task: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?
    private var pingLoop: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var url: URL?
    private(set) var symbols: [String] = []
    private var attempt = 0
    private var stopped = true

    /// Gọi trên main actor mỗi khi có tick mới.
    var onTick: ((Quote) -> Void)?
    var onStatus: ((Status) -> Void)?

    private(set) var status: Status = .idle {
        didSet { onStatus?(status) }
    }

    // MARK: - Điều khiển

    /// Đổi URL hoặc danh sách mã → kết nối lại khi cần.
    func configure(url newURL: URL?, symbols newSymbols: [String]) {
        let normalized = Array(Set(newSymbols.map { $0.uppercased() })).sorted()
        let urlChanged = newURL != url
        url = newURL
        symbols = normalized

        guard let newURL, !normalized.isEmpty else {
            stop()
            return
        }
        if urlChanged || task == nil {
            connect()
        } else if let task, task.state == .running {
            sendSubscribe()
        } else {
            connect()
        }
    }

    func stop() {
        stopped = true
        reconnectTask?.cancel()
        reconnectTask = nil
        pingLoop?.cancel()
        pingLoop = nil
        loop?.cancel()
        loop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        status = .idle
    }

    // MARK: - Kết nối

    private func connect() {
        guard let url, !symbols.isEmpty else { return }
        stopped = false
        status = attempt == 0 ? .connecting : .reconnecting

        loop?.cancel()
        pingLoop?.cancel()
        task?.cancel(with: .goingAway, reason: nil)

        let socket = URLSession.shared.webSocketTask(with: url)
        task = socket
        socket.resume()

        sendSubscribe()

        loop = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(socket: socket)
        }
        pingLoop = Task { [weak self] in
            guard let self else { return }
            await self.pingForever()
        }
    }

    private func sendSubscribe() {
        guard let task, task.state == .running, !symbols.isEmpty else { return }
        let payload: [String: Any] = [
            "id": "pulse-ticks",
            "subscribe": ["event": "ticks", "instruments": symbols]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self, weak task] error in
            guard error != nil else { return }
            Task { @MainActor [weak self, weak task] in
                guard let self, let task, task === self.task else { return }
                self.scheduleReconnect()
            }
        }
    }

    private func receiveLoop(socket: URLSessionWebSocketTask) async {
        // Chỉ nhận trên socket hiện hành; socket cũ bị huỷ sẽ bỏ qua lỗi (tránh kết nối đôi).
        while !stopped, socket === task, socket.state == .running {
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    handle(text: text)
                case .data(let data):
                    handle(text: String(data: data, encoding: .utf8) ?? "")
                @unknown default:
                    break
                }
                attempt = 0
                if status != .live { status = .live }
            } catch {
                if stopped || socket !== task { return }
                scheduleReconnect()
                return
            }
        }
    }

    /// Ping giữ kết nối mỗi 25 giây (một số proxy ngắt kết nối im lặng sau ~60 giây).
    private func pingForever() async {
        while !stopped {
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            if stopped { return }
            guard let current = task, current === self.task else { return }
            current.sendPing { [weak self, weak current] error in
                guard error != nil else { return }
                Task { @MainActor [weak self, weak current] in
                    guard let self, let current, current === self.task else { return }
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard !stopped, reconnectTask == nil else { return }
        status = .reconnecting
        attempt += 1
        let delay = min(30.0, pow(2.0, Double(min(attempt, 5))))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !self.stopped else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }

    // MARK: - Parse

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let quote = Self.parse(data: data) else { return }
        if symbols.contains(quote.symbol.uppercased()) {
            onTick?(quote)
        }
    }

    /// Chấp nhận bid/ask dạng số hoặc chuỗi, timestamp ISO hoặc epoch (s/ms).
    nonisolated static func parse(data: Data) -> Quote? {
        struct LooseTick: Decodable {
            let instrument: String
            let bid: FlexibleDouble
            let ask: FlexibleDouble
            let timestamp: FlexibleDate?
        }
        guard let tick = try? JSONDecoder().decode(LooseTick.self, from: data) else { return nil }
        let date: Date?
        if let stamp = tick.timestamp?.number {
            if stamp > 10_000_000_000 {
                date = Date(timeIntervalSince1970: stamp / 1000)
            } else if stamp > 1_000_000_000 {
                date = Date(timeIntervalSince1970: stamp)
            } else {
                date = nil
            }
        } else if let raw = tick.timestamp?.text, let parsed = Fmt.parseDate(raw) {
            date = parsed
        } else {
            date = nil
        }
        return Quote(symbol: tick.instrument.uppercased(),
                     bid: tick.bid.value,
                     ask: tick.ask.value,
                     timestamp: date)
    }
}

/// Giá JSON có thể là number hoặc chuỗi số.
struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let text = try? container.decode(String.self), let double = Double(text) {
            value = double
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Không phải số")
        }
    }
}

/// Thời điểm JSON: number (epoch s/ms) hoặc chuỗi ISO-8601.
struct FlexibleDate: Decodable {
    let number: Double?
    let text: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            number = double
            text = nil
        } else if let string = try? container.decode(String.self) {
            number = nil
            text = string
        } else {
            number = nil
            text = nil
        }
    }
}
