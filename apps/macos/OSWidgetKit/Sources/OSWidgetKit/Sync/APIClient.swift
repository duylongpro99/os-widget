import Foundation

/// Where the client endpoints live and the token to call them with.
public struct ServerCredentials: Sendable, Hashable {
    public let workerURL: URL
    public let clientToken: String

    public init(workerURL: URL, clientToken: String) {
        self.workerURL = workerURL
        self.clientToken = clientToken
    }
}

/// Why a call to the Worker failed.
public enum APIError: Error, Equatable, Sendable {
    /// The Worker URL or the client token is missing.
    case notConfigured
    /// No response arrived: network down, DNS, TLS, timeout.
    case network
    /// The server answered with a status this call does not accept.
    case status(Int)
    /// The response body is not what the API returns.
    case decoding

    /// True for failures worth retrying soon: no response, a server error, a timeout or a rate limit.
    public var isTemporary: Bool {
        switch self {
        case .network: true
        case .status(let code): code == 408 || code == 429 || code >= 500
        case .notConfigured, .decoding: false
        }
    }

    /// True when the token is missing, wrong or of the wrong kind.
    public var isAuthFailure: Bool {
        self == .status(401) || self == .status(403)
    }
}

/// The client endpoints of the Worker (architecture §4.1).
///
/// The credentials are read on every call, so a token or URL changed in the settings applies to the
/// next request.
public struct APIClient: Sendable {
    public static let timeout: TimeInterval = 15
    /// The largest page `GET /events` serves.
    public static let eventPageSize = 100

    private let credentials: @Sendable () -> ServerCredentials?
    private let transport: any HTTPTransport

    public init(credentials: @escaping @Sendable () -> ServerCredentials?, transport: any HTTPTransport = URLSessionTransport()) {
        self.credentials = credentials
        self.transport = transport
    }

    /// True when a URL and a token are available.
    public var isConfigured: Bool {
        credentials() != nil
    }

    /// `GET /items`: every live item and the `seq` read before the list.
    public func getItems() async throws(APIError) -> ItemsResponse {
        let response = try await send(method: "GET", path: ["items"])
        guard response.status == 200 else { throw .status(response.status) }
        do {
            return try ServerJSON.makeDecoder().decode(ItemsResponse.self, from: response.body)
        } catch {
            throw .decoding
        }
    }

    /// `GET /events?since=&limit=`: events after `since`, oldest first. An event that cannot be read is
    /// skipped so one bad row never blocks the cursor.
    public func getEvents(since: Int64, limit: Int = eventPageSize) async throws(APIError) -> [ServerEvent] {
        let query = [URLQueryItem(name: "since", value: String(since)), URLQueryItem(name: "limit", value: String(limit))]
        let response = try await send(method: "GET", path: ["events"], query: query)
        guard response.status == 200 else { throw .status(response.status) }
        do {
            return try ServerJSON.makeDecoder().decode(LossyArray<ServerEvent>.self, from: response.body).elements
        } catch {
            throw .decoding
        }
    }

    /// `PATCH /items/{id}` with `{"read": read}`. Returns the status code, whatever it is.
    public func patchRead(id: String, read: Bool) async throws(APIError) -> Int {
        let body = Data(#"{"read":\#(read)}"#.utf8)
        return try await send(method: "PATCH", path: ["items", id], body: body).status
    }

    /// `DELETE /items/{id}`. Returns the status code, whatever it is.
    public func delete(id: String) async throws(APIError) -> Int {
        try await send(method: "DELETE", path: ["items", id]).status
    }

    private func send(method: String, path: [String], query: [URLQueryItem] = [], body: Data? = nil) async throws(APIError) -> HTTPResponse {
        guard let credentials = credentials() else { throw .notConfigured }
        var url = credentials.workerURL
        for component in path {
            // The id goes into the path exactly as the server returned it; only percent-encoded.
            url.append(path: component, directoryHint: .notDirectory)
        }
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = method
        request.setValue("Bearer \(credentials.clientToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            return try await transport.send(request)
        } catch {
            throw .network
        }
    }
}
