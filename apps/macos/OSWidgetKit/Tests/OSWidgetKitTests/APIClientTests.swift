import Foundation
import Synchronization
import Testing
@testable import OSWidgetKit

@Suite("API client")
struct APIClientTests {
    private func client(_ transport: any HTTPTransport, credentials: ServerCredentials? = SyncTestData.credentials) -> APIClient {
        APIClient(credentials: { credentials }, transport: transport)
    }

    @Test func getItemsSendsTheClientTokenAndDecodesTheFixture() async throws {
        let transport = CannedTransport(HTTPResponse(status: 200, body: try Fixture.data("items")))
        let response = try await client(transport).getItems()

        let expected = try Fixture.items()
        #expect(response.seq == expected.seq)
        #expect(response.items.map(\.id) == expected.items.map(\.id))

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://worker.test/items")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-client-token")
        #expect(request.timeoutInterval == 15)
    }

    @Test func getEventsSendsSinceAndLimitAndDecodesTheFixture() async throws {
        let transport = CannedTransport(HTTPResponse(status: 200, body: try Fixture.data("events")))
        let events = try await client(transport).getEvents(since: 363, limit: 100)

        #expect(events.map(\.seq) == (try Fixture.events()).map(\.seq))
        let url = try #require(transport.requests.first?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/events")
        #expect(components.queryItems == [URLQueryItem(name: "since", value: "363"), URLQueryItem(name: "limit", value: "100")])
    }

    @Test func oneUnreadableEventDoesNotHideTheOthers() async throws {
        let body = #"[{"seq": 1, "type": "item.read", "item_id": "a"}, {"type": "item.read"}, {"seq": 3, "type": "item.deleted", "item_id": "b"}]"#
        let transport = CannedTransport(HTTPResponse(status: 200, body: Data(body.utf8)))
        let events = try await client(transport).getEvents(since: 0)
        #expect(events.map(\.seq) == [1, 3])
    }

    @Test func patchAndDeleteUseTheItemIdAsReturnedAndReturnTheStatus() async throws {
        let transport = CannedTransport(HTTPResponse(status: 204))
        let api = client(transport)
        let id = "6a48d5d0-4e73-4abd-b77f-8aac42c3373b"

        #expect(try await api.patchRead(id: id, read: true) == 204)
        #expect(try await api.patchRead(id: id, read: false) == 204)
        #expect(try await api.delete(id: id) == 204)

        let requests = transport.requests
        #expect(requests.map(\.httpMethod) == ["PATCH", "PATCH", "DELETE"])
        #expect(requests.allSatisfy { $0.url?.absoluteString == "https://worker.test/items/\(id)" })
        #expect(requests.map { $0.httpBody.map { String(decoding: $0, as: UTF8.self) } } == [#"{"read":true}"#, #"{"read":false}"#, nil])
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-client-token" })
    }

    @Test func patchReturnsErrorStatusesInsteadOfThrowing() async throws {
        let api = client(CannedTransport(HTTPResponse(status: 404)))
        #expect(try await api.patchRead(id: "a", read: true) == 404)
        #expect(try await api.delete(id: "a") == 404)
    }

    @Test func failuresMapToAPIErrors() async throws {
        await #expect(throws: APIError.status(401)) {
            _ = try await client(CannedTransport(HTTPResponse(status: 401))).getItems()
        }
        await #expect(throws: APIError.status(503)) {
            _ = try await client(CannedTransport(HTTPResponse(status: 503))).getEvents(since: 0)
        }
        await #expect(throws: APIError.decoding) {
            _ = try await client(CannedTransport(HTTPResponse(status: 200, body: Data("nope".utf8)))).getItems()
        }
        await #expect(throws: APIError.network) {
            _ = try await client(CannedTransport(failing: URLError(.notConnectedToInternet))).patchRead(id: "a", read: true)
        }

        let transport = CannedTransport(HTTPResponse(status: 200))
        await #expect(throws: APIError.notConfigured) {
            _ = try await client(transport, credentials: nil).getItems()
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func credentialsAreReadOnEveryCall() async throws {
        let token = Mutex("first-token")
        let transport = CannedTransport(HTTPResponse(status: 204))
        let api = APIClient(
            credentials: { ServerCredentials(workerURL: SyncTestData.workerURL, clientToken: token.withLock { $0 }) },
            transport: transport
        )
        _ = try await api.delete(id: "a")
        token.withLock { $0 = "second-token" }
        _ = try await api.delete(id: "a")
        #expect(transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer first-token", "Bearer second-token"])
    }

    @Test func errorClassification() {
        #expect(APIError.network.isTemporary)
        #expect(APIError.status(503).isTemporary)
        #expect(APIError.status(429).isTemporary)
        #expect(!APIError.status(400).isTemporary)
        #expect(APIError.status(401).isAuthFailure)
        #expect(APIError.status(403).isAuthFailure)
        #expect(!APIError.decoding.isTemporary)
    }
}
