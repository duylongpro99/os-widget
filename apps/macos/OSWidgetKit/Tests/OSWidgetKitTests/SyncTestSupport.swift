import Foundation
import Synchronization
import Testing
@testable import OSWidgetKit

/// Collects log lines instead of sending them to `os.Logger`.
final class LogRecorder: Sendable {
    private let lines = Mutex<[String]>([])

    var log: SyncLog { SyncLog { [self] line in lines.withLock { $0.append(line) } } }
    var all: [String] { lines.withLock { $0 } }

    func count(_ prefix: String) -> Int {
        all.count { $0.hasPrefix(prefix) }
    }
}

final class Counter: Sendable {
    private let value = Mutex(0)

    var count: Int { value.withLock { $0 } }

    func increment() {
        value.withLock { $0 += 1 }
    }
}

/// Polls `condition` until it holds or `timeout` passes.
func eventually(timeout: Duration = .seconds(3), _ condition: @Sendable () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

enum SyncTestData {
    static let workerURL = URL(string: "https://worker.test")!
    static let credentials = ServerCredentials(workerURL: workerURL, clientToken: "test-client-token")

    /// A sleep that never completes, so a retry scheduled by the engine never fires during a test.
    static let neverSleep: @Sendable (Duration) async throws -> Void = { _ in throw CancellationError() }
}

struct SyncTestSignal: ChangeSignal {
    let signals: AsyncStream<Void>
}

/// A request as the fake server saw it.
struct RecordedRequest: Sendable, Hashable {
    let method: String
    let path: String
    let query: [String: String]
    let authorization: String?
    let body: Data?

    var line: String {
        let query = query.keys.sorted().map { "\($0)=\(self.query[$0]!)" }.joined(separator: "&")
        return query.isEmpty ? "\(method) \(path)" : "\(method) \(path)?\(query)"
    }
}

/// An in-memory Worker: items, an event log with `seq`, the client endpoints, plus switches for network
/// failure, forced statuses and holding a request until the test releases it.
final class FakeServer: HTTPTransport {
    private struct State {
        var items: [Item] = []
        var events: [ServerEvent] = []
        var seq: Int64 = 0
        var requests: [RecordedRequest] = []
        var offline = false
        /// Statuses returned, in order, by the next `PATCH` or `DELETE` calls of an item id.
        var forcedStatuses: [String: [Int]] = [:]
        var gate: AsyncStream<Void>?
        var gateOpen: AsyncStream<Void>.Continuation?
    }

    private let state = Mutex(State())

    var requests: [RecordedRequest] { state.withLock { $0.requests } }
    var requestLines: [String] { requests.map(\.line) }
    var seq: Int64 { state.withLock { $0.seq } }

    func setOffline(_ offline: Bool) {
        state.withLock { $0.offline = offline }
    }

    func force(_ statuses: [Int], for id: String) {
        state.withLock { $0.forcedStatuses[id] = statuses }
    }

    /// Holds every request from now on until `release()`.
    func hold() {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        state.withLock {
            $0.gate = stream
            $0.gateOpen = continuation
        }
    }

    func release() {
        let open = state.withLock { state -> AsyncStream<Void>.Continuation? in
            defer {
                state.gate = nil
                state.gateOpen = nil
            }
            return state.gateOpen
        }
        open?.finish()
    }

    // MARK: Server-side changes

    /// Stores `item` and logs `item.created`.
    func publish(_ item: Item) {
        state.withLock { state in
            state.items.append(item)
            state.seq += 1
            state.events.append(ServerEvent(seq: state.seq, type: .created, itemId: item.id, item: item, createdAt: item.createdAt))
        }
    }

    /// Logs an event without an item (for paging tests).
    func logEvent(_ type: ServerEvent.EventType, id: String) {
        state.withLock { state in
            state.seq += 1
            state.events.append(ServerEvent(seq: state.seq, type: type, itemId: id, createdAt: TestData.now))
        }
    }

    /// Another device marks `id` read.
    func markRead(_ id: String) {
        state.withLock { state in
            guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
            state.items[index].readAt = TestData.now
            state.seq += 1
            state.events.append(ServerEvent(seq: state.seq, type: .read, itemId: id, createdAt: TestData.now))
        }
    }

    /// Removes `id` without an event, as the daily purge does.
    func purge(_ id: String) {
        state.withLock { $0.items.removeAll { $0.id == id } }
    }

    // MARK: HTTPTransport

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let recorded = RecordedRequest(
            method: request.httpMethod ?? "GET",
            path: components.path,
            query: Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }),
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: request.httpBody
        )
        let gate = state.withLock { $0.gate }
        if let gate {
            for await _ in gate {}
        }
        return try state.withLock { state in
            guard !state.offline else { throw URLError(.notConnectedToInternet) }
            state.requests.append(recorded)
            return try Self.respond(to: recorded, state: &state)
        }
    }

    private static func respond(to request: RecordedRequest, state: inout State) throws -> HTTPResponse {
        let parts = request.path.split(separator: "/").map(String.init)
        switch (request.method, parts.count, parts.first) {
        case ("GET", 1, "items"):
            let body = ItemsBody(seq: state.seq, items: state.items.filter { !$0.isDeleted })
            return HTTPResponse(status: 200, body: try ServerJSON.makeEncoder().encode(body))
        case ("GET", 1, "events"):
            let since = Int64(request.query["since"] ?? "") ?? -1
            let limit = Int(request.query["limit"] ?? "") ?? 100
            let page = state.events.filter { $0.seq > since }.prefix(min(limit, 100)).map(EventBody.init)
            return HTTPResponse(status: 200, body: try ServerJSON.makeEncoder().encode(Array(page)))
        case ("PATCH", 2, "items"), ("DELETE", 2, "items"):
            let id = parts[1]
            if var forced = state.forcedStatuses[id], !forced.isEmpty {
                let status = forced.removeFirst()
                state.forcedStatuses[id] = forced
                return HTTPResponse(status: status)
            }
            guard let index = state.items.firstIndex(where: { $0.id == id && !$0.isDeleted }) else {
                return HTTPResponse(status: 404)
            }
            state.seq += 1
            if request.method == "DELETE" {
                state.items[index].deletedAt = TestData.now
                state.events.append(ServerEvent(seq: state.seq, type: .deleted, itemId: id, createdAt: TestData.now))
            } else {
                let read = String(decoding: request.body ?? Data(), as: UTF8.self).contains("true")
                state.items[index].readAt = read ? TestData.now : nil
                state.events.append(ServerEvent(seq: state.seq, type: read ? .read : .unread, itemId: id, createdAt: TestData.now))
            }
            return HTTPResponse(status: 204)
        default:
            return HTTPResponse(status: 404)
        }
    }

    private struct ItemsBody: Encodable {
        let seq: Int64
        let items: [Item]
    }

    private struct EventBody: Encodable {
        let seq: Int64
        let type: String
        let itemId: String
        let createdAt: Date?
        let item: Item?
        let hasItem: Bool

        init(_ event: ServerEvent) {
            seq = event.seq
            type = event.type.rawValue
            itemId = event.itemId
            createdAt = event.createdAt
            item = event.item
            hasItem = event.type == .created
        }

        enum CodingKeys: String, CodingKey {
            case seq, type, item
            case itemId = "item_id"
            case createdAt = "created_at"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(seq, forKey: .seq)
            try c.encode(type, forKey: .type)
            try c.encode(itemId, forKey: .itemId)
            try c.encodeIfPresent(createdAt, forKey: .createdAt)
            if hasItem { try c.encode(item, forKey: .item) }
        }
    }
}

/// A transport that answers every request with one canned response and records the requests.
final class CannedTransport: HTTPTransport {
    private let response: Mutex<Result<HTTPResponse, URLError>>
    private let recorded = Mutex<[URLRequest]>([])

    init(_ response: HTTPResponse) {
        self.response = Mutex(.success(response))
    }

    init(failing error: URLError) {
        response = Mutex(.failure(error))
    }

    var requests: [URLRequest] { recorded.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        recorded.withLock { $0.append(request) }
        return try response.withLock { $0 }.get()
    }
}

// MARK: - WebSocket

/// A scripted Realtime server on one connection.
final class FakeWebSocket: WebSocketConnection {
    struct Behavior: Sendable {
        /// Status of the automatic reply to the join; `nil` sends no reply.
        var joinStatus: String? = "ok"
        var replyToHeartbeats = true
    }

    private struct State {
        var sent: [String] = []
        var buffer: [String] = []
        var waiter: CheckedContinuation<String, Error>?
        var closed = false
    }

    private let behavior: Behavior
    private let state = Mutex(State())

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    var sent: [PhoenixMessage] { state.withLock { $0.sent }.compactMap(PhoenixMessage.decode) }
    var isClosed: Bool { state.withLock { $0.closed } }

    func send(_ text: String) async throws {
        let closed = state.withLock { state in
            state.sent.append(text)
            return state.closed
        }
        if closed { throw URLError(.networkConnectionLost) }
        guard let message = PhoenixMessage.decode(text) else { return }
        if message.event == "phx_join", let status = behavior.joinStatus {
            push(reply(to: message, status: status))
        } else if message.event == "heartbeat", behavior.replyToHeartbeats {
            push(reply(to: message, status: "ok"))
        }
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let result: Result<String, Error>? = state.withLock { state in
                if state.closed { return .failure(URLError(.networkConnectionLost)) }
                if !state.buffer.isEmpty { return .success(state.buffer.removeFirst()) }
                state.waiter = continuation
                return nil
            }
            if let result { continuation.resume(with: result) }
        }
    }

    func close() {
        let waiter = state.withLock { state in
            state.closed = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(throwing: URLError(.networkConnectionLost))
    }

    /// Sends a frame from the server.
    func push(_ text: String) {
        let waiter = state.withLock { state -> CheckedContinuation<String, Error>? in
            guard !state.closed else { return nil }
            if let waiter = state.waiter {
                state.waiter = nil
                return waiter
            }
            state.buffer.append(text)
            return nil
        }
        waiter?.resume(returning: text)
    }

    func push(_ message: PhoenixMessage) {
        push(message.encoded())
    }

    private func reply(to message: PhoenixMessage, status: String) -> String {
        PhoenixMessage(
            topic: message.topic,
            event: "phx_reply",
            payload: .object(["status": .string(status), "response": .object([:])]),
            ref: message.ref,
            joinRef: message.joinRef
        ).encoded()
    }
}

/// Hands out a new `FakeWebSocket` on every connect and keeps them all.
final class FakeSocketFactory: Sendable {
    private let sockets = Mutex<[FakeWebSocket]>([])
    private let behavior: @Sendable (Int) -> FakeWebSocket.Behavior

    init(behavior: @escaping @Sendable (Int) -> FakeWebSocket.Behavior = { _ in .init() }) {
        self.behavior = behavior
    }

    var all: [FakeWebSocket] { sockets.withLock { $0 } }
    var count: Int { all.count }
    var latest: FakeWebSocket? { all.last }

    var connect: @Sendable () -> (any WebSocketConnection)? {
        { [self] in
            sockets.withLock { sockets in
                let socket = FakeWebSocket(behavior: behavior(sockets.count))
                sockets.append(socket)
                return socket
            }
        }
    }
}
