import Foundation
import Testing
@testable import OSWidgetKit

@Suite("Realtime signal")
struct RealtimeSignalTests {
    // MARK: Messages

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    @Test func joinEncodesTheChannelAndTheInsertSubscription() throws {
        let value = try json(PhoenixMessage.join(ref: "1").encoded())
        #expect(value["topic"] == .string("realtime:os-widget-events"))
        #expect(value["event"] == .string("phx_join"))
        #expect(value["ref"] == .string("1"))
        #expect(value["join_ref"] == .string("1"))
        let change = value["payload"]?["config"]?["postgres_changes"]?.arrayValue?.first
        #expect(change == .object(["event": .string("INSERT"), "schema": .string("public"), "table": .string("events")]))
    }

    @Test func heartbeatEncodesPhoenixTopicAndEmptyPayload() throws {
        let value = try json(PhoenixMessage.heartbeat(ref: "7").encoded())
        #expect(value["topic"] == .string("phoenix"))
        #expect(value["event"] == .string("heartbeat"))
        #expect(value["payload"] == .object([:]))
        #expect(value["ref"] == .string("7"))
        #expect(value["join_ref"] == .null)
    }

    @Test func messagesRoundTrip() {
        let join = PhoenixMessage.join(ref: "3")
        #expect(PhoenixMessage.decode(join.encoded()) == join)
    }

    @Test(arguments: [
        (#"{"topic":"realtime:os-widget-events","event":"phx_reply","payload":{"status":"ok","response":{"postgres_changes":[{"id":1}]}},"ref":"1","join_ref":"1"}"#, RealtimeIncoming.joined),
        (#"{"topic":"realtime:os-widget-events","event":"phx_reply","payload":{"status":"error","response":{"reason":"denied"}},"ref":"1","join_ref":"1"}"#, .channelError),
        (#"{"topic":"realtime:os-widget-events","event":"phx_reply","payload":{"status":"error"},"ref":"5","join_ref":"1"}"#, .channelError),
        (#"{"topic":"phoenix","event":"phx_reply","payload":{"status":"ok","response":{}},"ref":"2","join_ref":null}"#, .heartbeatReply(ref: "2")),
        (#"{"topic":"realtime:os-widget-events","event":"postgres_changes","payload":{"data":{"type":"INSERT"}},"ref":null}"#, .change),
        (#"{"topic":"realtime:os-widget-events","event":"phx_error","payload":{},"ref":"1"}"#, .channelError),
        (#"{"topic":"realtime:os-widget-events","event":"phx_close","payload":{},"ref":"1"}"#, .channelError),
        (#"{"topic":"realtime:os-widget-events","event":"system","payload":{"status":"ok","message":"Subscribed"},"ref":null}"#, .ignored),
        (#"{"topic":"realtime:os-widget-events","event":"presence_state","payload":{},"ref":null}"#, .ignored),
        (#"{"topic":"realtime:os-widget-events""#, .ignored),
        ("not json", .ignored),
    ])
    func classifiesReceivedMessages(text: String, expected: RealtimeIncoming) {
        #expect(RealtimeIncoming.classify(PhoenixMessage.decode(text), joinRef: "1") == expected)
    }

    @Test func socketURLCarriesTheKeyAndProtocolVersion() throws {
        let url = try #require(RealtimeSignal.socketURL(supabaseURL: URL(string: "https://project.supabase.co")!, publishableKey: "sb_publishable_test"))
        #expect(url.absoluteString == "wss://project.supabase.co/realtime/v1/websocket?apikey=sb_publishable_test&vsn=1.0.0")
        #expect(RealtimeSignal.socketURL(supabaseURL: URL(string: "https://project.supabase.co")!, publishableKey: "") == nil)
    }

    // MARK: Backoff

    @Test func backoffDoublesUpToSixtySecondsAndResets() {
        var policy = ReconnectPolicy()
        let delays = (0..<8).map { _ in policy.nextDelay() }
        #expect(delays == [1, 2, 4, 8, 16, 32, 60, 60].map { Duration.seconds($0) })
        policy.reset()
        #expect(policy.nextDelay() == .seconds(1))
    }

    // MARK: Connection

    private func makeSignal(
        _ factory: FakeSocketFactory,
        heartbeat: Duration = .seconds(60),
        logs: LogRecorder = LogRecorder()
    ) -> RealtimeSignal {
        RealtimeSignal(
            connect: factory.connect,
            heartbeatInterval: heartbeat,
            reconnect: ReconnectPolicy(initial: .milliseconds(10), maximum: .milliseconds(50)),
            log: logs.log
        )
    }

    /// Counts the signals emitted until the returned task is cancelled.
    private func count(_ signal: RealtimeSignal) -> (Counter, Task<Void, Never>) {
        let counter = Counter()
        let task = Task {
            for await _ in signal.signals {
                counter.increment()
            }
        }
        return (counter, task)
    }

    @Test func joinAndEachChangeEmitASignalButHeartbeatRepliesDoNot() async throws {
        let factory = FakeSocketFactory()
        let logs = LogRecorder()
        let signal = makeSignal(factory, heartbeat: .milliseconds(20), logs: logs)
        let (counter, counting) = count(signal)
        await signal.start()

        let joined = await eventually { counter.count == 1 }
        #expect(joined)
        let socket = try #require(factory.latest)
        let change = PhoenixMessage(topic: PhoenixMessage.channelTopic, event: "postgres_changes", payload: .object([:]), ref: nil, joinRef: nil)
        socket.push(change)
        socket.push(change)
        let changes = await eventually { counter.count == 3 }
        #expect(changes)

        let heartbeats = await eventually { socket.sent.count(where: { $0.event == "heartbeat" }) >= 3 }
        #expect(heartbeats)
        #expect(counter.count == 3)
        #expect(factory.count == 1)
        #expect(logs.all.contains("realtime.state joined"))

        let sent = socket.sent
        #expect(sent.first?.event == "phx_join")
        let refs = sent.compactMap { $0.ref.flatMap(Int.init) }
        #expect(refs == Array(1...refs.count))

        await signal.stop()
        counting.cancel()
    }

    @Test func aClosedSocketIsOpenedAgain() async throws {
        let factory = FakeSocketFactory()
        let signal = makeSignal(factory)
        let (counter, counting) = count(signal)
        await signal.start()

        let first = await eventually { counter.count == 1 }
        #expect(first)
        try #require(factory.latest).close()

        let reopened = await eventually { factory.count == 2 && counter.count == 2 }
        #expect(reopened)
        #expect(factory.all[0].isClosed)
        #expect(factory.all[1].sent.first?.event == "phx_join")

        await signal.stop()
        counting.cancel()
    }

    @Test func aHeartbeatWithoutReplyReopensTheSocket() async {
        let factory = FakeSocketFactory { index in
            FakeWebSocket.Behavior(joinStatus: "ok", replyToHeartbeats: index > 0)
        }
        let logs = LogRecorder()
        let signal = makeSignal(factory, heartbeat: .milliseconds(20), logs: logs)
        await signal.start()

        let reopened = await eventually { factory.count == 2 }
        #expect(reopened)
        #expect(factory.all[0].isClosed)
        #expect(factory.all[0].sent.count(where: { $0.event == "heartbeat" }) == 1)
        #expect(logs.all.contains("realtime.state heartbeat_timeout"))

        await signal.stop()
    }

    @Test func aRefusedJoinReopensTheSocket() async {
        let factory = FakeSocketFactory { index in
            FakeWebSocket.Behavior(joinStatus: index == 0 ? "error" : "ok")
        }
        let signal = makeSignal(factory)
        let (counter, counting) = count(signal)
        await signal.start()

        let reopened = await eventually { factory.count == 2 && counter.count == 1 }
        #expect(reopened)
        #expect(factory.all[0].isClosed)

        await signal.stop()
        counting.cancel()
    }

    @Test func stopClosesTheSocketAndDoesNotReconnect() async throws {
        let factory = FakeSocketFactory()
        let signal = makeSignal(factory)
        await signal.start()
        let open = await eventually { factory.count == 1 }
        #expect(open)

        await signal.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(factory.count == 1)
        #expect(try #require(factory.latest).isClosed)

        await signal.start()
        let restarted = await eventually { factory.count == 2 }
        #expect(restarted)
        await signal.stop()
    }

    @Test func missingSettingsOpenNoSocket() async {
        let logs = LogRecorder()
        let signal = RealtimeSignal(connect: { nil }, log: logs.log)
        await signal.start()
        let logged = await eventually { logs.all.contains("realtime.state not_configured") }
        #expect(logged)
    }

    // MARK: Live

    /// Connects to a real Supabase project and waits for the join and one `INSERT` on `events`.
    /// Runs only with `OSWIDGET_LIVE_REALTIME=1`, `OSWIDGET_SUPABASE_URL` and `OSWIDGET_SUPABASE_KEY`
    /// set; something else must insert an event while it waits. Received frames are printed with the
    /// prefix `realtime.frame` so the join reply can be read; they contain no key.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OSWIDGET_LIVE_REALTIME"] == "1"))
    func liveJoinAndInsert() async throws {
        let environment = ProcessInfo.processInfo.environment
        let supabaseURL = try #require(environment["OSWIDGET_SUPABASE_URL"].flatMap(URL.init(string:)))
        let key = try #require(environment["OSWIDGET_SUPABASE_KEY"])
        let url = try #require(RealtimeSignal.socketURL(supabaseURL: supabaseURL, publishableKey: key))
        let logs = LogRecorder()
        let signal = RealtimeSignal(
            connect: { SyncPrintingSocket(URLSessionWebSocket(url: url)) },
            log: SyncLog { line in
                print(line)
                logs.log(line)
            }
        )
        let (counter, counting) = count(signal)
        await signal.start()

        let joined = await eventually(timeout: .seconds(20)) { counter.count >= 1 }
        #expect(joined)
        print("realtime.live waiting_for_insert")
        let inserted = await eventually(timeout: .seconds(120)) { counter.count >= 2 }
        #expect(inserted)
        print("realtime.live insert_signal=\(inserted)")

        await signal.stop()
        counting.cancel()
    }
}

/// Prints every received frame, for the live check.
private struct SyncPrintingSocket: WebSocketConnection {
    let base: any WebSocketConnection

    init(_ base: any WebSocketConnection) {
        self.base = base
    }

    func send(_ text: String) async throws {
        try await base.send(text)
    }

    func receive() async throws -> String {
        let text = try await base.receive()
        print("realtime.frame \(text)")
        return text
    }

    func close() {
        base.close()
    }
}
