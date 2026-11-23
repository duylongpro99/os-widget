import Foundation

/// A stream of hints that the server has something new. A hint carries no data: the receiver fetches.
public protocol ChangeSignal: Sendable {
    var signals: AsyncStream<Void> { get }
}

/// One WebSocket connection, already opened. `receive` throws once the connection is closed or fails.
/// Tests replace the real socket with a fake.
public protocol WebSocketConnection: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close()
}

// MARK: - Messages

/// A message of the Phoenix channel protocol that Supabase Realtime speaks (serializer `vsn=1.0.0`:
/// one JSON object per frame).
public struct PhoenixMessage: Codable, Sendable, Hashable {
    /// The channel that carries `INSERT`s on `public.events`.
    public static let channelTopic = "realtime:os-widget-events"

    public var topic: String
    public var event: String
    public var payload: JSONValue
    public var ref: String?
    public var joinRef: String?

    public init(topic: String, event: String, payload: JSONValue, ref: String?, joinRef: String?) {
        self.topic = topic
        self.event = event
        self.payload = payload
        self.ref = ref
        self.joinRef = joinRef
    }

    enum CodingKeys: String, CodingKey {
        case topic, event, payload, ref
        case joinRef = "join_ref"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(topic, forKey: .topic)
        try c.encode(event, forKey: .event)
        try c.encode(payload, forKey: .payload)
        try c.encode(ref, forKey: .ref)
        try c.encode(joinRef, forKey: .joinRef)
    }

    /// Joins the channel, asking for `INSERT`s on `public.events`.
    public static func join(ref: String) -> PhoenixMessage {
        let change: JSONValue = .object(["event": .string("INSERT"), "schema": .string("public"), "table": .string("events")])
        let payload: JSONValue = .object(["config": .object(["postgres_changes": .array([change])])])
        return PhoenixMessage(topic: channelTopic, event: "phx_join", payload: payload, ref: ref, joinRef: ref)
    }

    public static func heartbeat(ref: String) -> PhoenixMessage {
        PhoenixMessage(topic: "phoenix", event: "heartbeat", payload: .object([:]), ref: ref, joinRef: nil)
    }

    public func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding plain strings and JSON values cannot fail.
        let data = (try? encoder.encode(self)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Decodes one frame, or returns `nil` when it is not a Phoenix message.
    public static func decode(_ text: String) -> PhoenixMessage? {
        try? JSONDecoder().decode(PhoenixMessage.self, from: Data(text.utf8))
    }
}

/// What a received message means for the client.
public enum RealtimeIncoming: Sendable, Hashable {
    /// The join was accepted: the channel is subscribed.
    case joined
    case heartbeatReply(ref: String?)
    /// A row was inserted into `events`.
    case change
    /// The channel failed, closed or refused the join; the connection should be opened again.
    case channelError
    /// Anything else (`system`, `presence_state`, unreadable frames).
    case ignored

    /// Classifies `message`, where `joinRef` is the ref of the join sent on this connection.
    public static func classify(_ message: PhoenixMessage?, joinRef: String?) -> RealtimeIncoming {
        guard let message else { return .ignored }
        switch message.event {
        case "phx_reply":
            if message.topic == "phoenix" { return .heartbeatReply(ref: message.ref) }
            let ok = message.payload["status"]?.stringValue == "ok"
            if message.ref != nil, message.ref == joinRef { return ok ? .joined : .channelError }
            return ok ? .ignored : .channelError
        case "postgres_changes":
            return message.topic == PhoenixMessage.channelTopic ? .change : .ignored
        case "phx_error", "phx_close":
            return message.topic == PhoenixMessage.channelTopic ? .channelError : .ignored
        default:
            return .ignored
        }
    }
}

// MARK: - Reconnecting

/// Exponential backoff: `initial`, twice that, four times … capped at `maximum`. `reset()` starts over.
public struct ReconnectPolicy: Sendable, Hashable {
    public let initial: Duration
    public let maximum: Duration
    public private(set) var attempt = 0

    public init(initial: Duration = .seconds(1), maximum: Duration = .seconds(60)) {
        self.initial = initial
        self.maximum = maximum
    }

    /// The delay before the next attempt.
    public mutating func nextDelay() -> Duration {
        let factor = 1 << min(attempt, 30)
        attempt += 1
        return min(initial * factor, maximum)
    }

    public mutating func reset() {
        attempt = 0
    }
}

// MARK: - Socket

/// The app's single Realtime connection, used only as a hint that `events` has new rows.
///
/// After the socket opens it joins `realtime:os-widget-events`, then sends a heartbeat every 25 seconds.
/// Every accepted join emits a signal (to catch up on what was missed while disconnected) and so does
/// every `postgres_changes`; their payloads are ignored. The socket is opened again after a backoff when
/// it closes or fails, when the join is refused, or when a heartbeat gets no reply before the next one.
public actor RealtimeSignal: ChangeSignal {
    public nonisolated let signals: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    /// Opens a connection, or returns `nil` when the Supabase URL or key is missing.
    private let connect: @Sendable () -> (any WebSocketConnection)?
    private let heartbeatInterval: Duration
    private let log: SyncLog
    private var policy: ReconnectPolicy
    private var runTask: Task<Void, Never>?
    private var connection: (any WebSocketConnection)?
    private var lastRef = 0

    public init(
        connect: @escaping @Sendable () -> (any WebSocketConnection)?,
        heartbeatInterval: Duration = .seconds(25),
        reconnect: ReconnectPolicy = ReconnectPolicy(),
        log: SyncLog = .system
    ) {
        (signals, continuation) = AsyncStream.makeStream(of: Void.self)
        self.connect = connect
        self.heartbeatInterval = heartbeatInterval
        self.policy = reconnect
        self.log = log
    }

    /// The Realtime endpoint of a Supabase project: `wss://<host>/realtime/v1/websocket?apikey=…&vsn=1.0.0`.
    public static func socketURL(supabaseURL: URL, publishableKey: String) -> URL? {
        guard let host = supabaseURL.host(), !host.isEmpty, !publishableKey.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = supabaseURL.scheme?.lowercased() == "http" ? "ws" : "wss"
        components.host = host
        components.port = supabaseURL.port
        components.path = "/realtime/v1/websocket"
        components.queryItems = [URLQueryItem(name: "apikey", value: publishableKey), URLQueryItem(name: "vsn", value: "1.0.0")]
        return components.url
    }

    /// Opens the connection unless it is already open or opening.
    public func start() {
        guard runTask == nil else { return }
        runTask = Task { await self.run() }
    }

    /// Closes the connection and stops reconnecting until `start()`.
    public func stop() {
        runTask?.cancel()
        runTask = nil
        connection?.close()
        connection = nil
    }

    private func run() async {
        while !Task.isCancelled {
            guard let connection = connect() else {
                log("realtime.state not_configured")
                runTask = nil
                return
            }
            self.connection = connection
            log("realtime.state connecting")
            await session(on: connection)
            connection.close()
            self.connection = nil
            if Task.isCancelled { break }
            let delay = policy.nextDelay()
            log("realtime.state reconnecting in=\(delay)")
            do {
                try await Task.sleep(for: delay)
            } catch {
                break
            }
        }
        log("realtime.state stopped")
    }

    private enum SessionEvent: Sendable {
        case message(String)
        case tick
        case closed
    }

    /// Runs one connection until it must be opened again or the task is cancelled.
    private func session(on connection: any WebSocketConnection) async {
        let (events, sink) = AsyncStream.makeStream(of: SessionEvent.self)
        let receiver = Task {
            while true {
                do {
                    sink.yield(.message(try await connection.receive()))
                } catch {
                    sink.yield(.closed)
                    return
                }
            }
        }
        let interval = heartbeatInterval
        let ticker = Task {
            while true {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                sink.yield(.tick)
            }
        }
        defer {
            receiver.cancel()
            ticker.cancel()
            sink.finish()
        }

        let joinRef = makeRef()
        guard await send(.join(ref: joinRef), on: connection) else { return }
        var pendingHeartbeat: String?

        for await event in events {
            switch event {
            case .tick:
                if pendingHeartbeat != nil {
                    log("realtime.state heartbeat_timeout")
                    return
                }
                let ref = makeRef()
                pendingHeartbeat = ref
                guard await send(.heartbeat(ref: ref), on: connection) else { return }
            case .message(let text):
                switch RealtimeIncoming.classify(PhoenixMessage.decode(text), joinRef: joinRef) {
                case .joined:
                    policy.reset()
                    log("realtime.state joined")
                    continuation.yield()
                case .heartbeatReply(let ref):
                    if ref == pendingHeartbeat { pendingHeartbeat = nil }
                case .change:
                    continuation.yield()
                case .channelError:
                    log("realtime.state channel_error")
                    return
                case .ignored:
                    continue
                }
            case .closed:
                log("realtime.state closed")
                return
            }
        }
    }

    private func send(_ message: PhoenixMessage, on connection: any WebSocketConnection) async -> Bool {
        do {
            try await connection.send(message.encoded())
            return true
        } catch {
            log("realtime.state send_failed")
            return false
        }
    }

    private func makeRef() -> String {
        lastRef += 1
        return String(lastRef)
    }
}

/// The real socket, on `URLSessionWebSocketTask`.
public final class URLSessionWebSocket: WebSocketConnection {
    private let task: URLSessionWebSocketTask

    public init(url: URL, session: URLSession = .shared) {
        task = session.webSocketTask(with: url)
        task.resume()
    }

    public func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    public func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let text):
            return text
        case .data(let data):
            return String(decoding: data, as: UTF8.self)
        @unknown default:
            return ""
        }
    }

    public func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}
