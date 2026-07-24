import Foundation

/// Thin async client for the Yamaha Extended Control HTTP API.
/// One instance per app; addresses devices by host (IP) per call.
public struct YXCClient: Sendable {
    let session: URLSession
    let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 4) {
        self.session = session
        self.timeout = timeout
    }

    // MARK: - Request plumbing

    func url(_ host: String, _ path: String, _ query: [String: String] = [:]) -> URL {
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = host
        comps.path = "/YamahaExtendedControl/v1/" + path
        if !query.isEmpty {
            comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return comps.url!
    }

    @discardableResult
    func get<T: Decodable>(_ host: String, _ path: String, _ query: [String: String] = [:], as type: T.Type) async throws -> T {
        var request = URLRequest(url: url(host, path, query), timeoutInterval: timeout)
        request.httpMethod = "GET"
        return try await run(request, host: host, endpoint: path)
    }

    func post<Body: Encodable, T: Decodable>(_ host: String, _ path: String, body: Body, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url(host, path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await run(request, host: host, endpoint: path)
    }

    private func run<T: Decodable>(_ request: URLRequest, host: String, endpoint: String) async throws -> T {
        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw HouseMusicError.deviceUnreachable(host)
        }
        let decoded = try JSONDecoder().decode(T.self, from: data)
        if let coded = decoded as? YXCResponseCode, coded.responseCode != 0 {
            throw HouseMusicError.yxcError(code: coded.responseCode, endpoint: endpoint)
        }
        if let code = (try? JSONDecoder().decode(YXCResponseCode.self, from: data))?.responseCode, code != 0 {
            throw HouseMusicError.yxcError(code: code, endpoint: endpoint)
        }
        return decoded
    }

    // MARK: - System

    public func deviceInfo(host: String) async throws -> YXCDeviceInfo {
        try await get(host, "system/getDeviceInfo", as: YXCDeviceInfo.self)
    }

    public func nameText(host: String) async throws -> YXCNameText {
        try await get(host, "system/getNameText", as: YXCNameText.self)
    }

    public func features(host: String) async throws -> YXCFeatures {
        try await get(host, "system/getFeatures", as: YXCFeatures.self)
    }

    // MARK: - Zone

    public func status(host: String, zone: String = "main") async throws -> YXCStatus {
        try await get(host, "\(zone)/getStatus", as: YXCStatus.self)
    }

    public func setPower(host: String, zone: String = "main", on: Bool) async throws {
        try await get(host, "\(zone)/setPower", ["power": on ? "on" : "standby"], as: YXCResponseCode.self)
    }

    public func setVolume(host: String, zone: String = "main", units: Int) async throws {
        try await get(host, "\(zone)/setVolume", ["volume": String(units)], as: YXCResponseCode.self)
    }

    public func setMute(host: String, zone: String = "main", muted: Bool) async throws {
        try await get(host, "\(zone)/setMute", ["enable": muted ? "true" : "false"], as: YXCResponseCode.self)
    }

    public func setInput(host: String, zone: String = "main", input: String) async throws {
        try await get(host, "\(zone)/setInput", ["input": input, "mode": "autoplay_disabled"], as: YXCResponseCode.self)
    }

    public func setPureDirect(host: String, zone: String = "main", enabled: Bool) async throws {
        try await get(host, "\(zone)/setPureDirect", ["enable": enabled ? "true" : "false"], as: YXCResponseCode.self)
    }

    // MARK: - netusb (Spotify et al playback on the device)

    public func playInfo(host: String) async throws -> YXCPlayInfo {
        try await get(host, "netusb/getPlayInfo", as: YXCPlayInfo.self)
    }

    public func setPlayback(host: String, _ action: String) async throws {
        try await get(host, "netusb/setPlayback", ["playback": action], as: YXCResponseCode.self)
    }

    // MARK: - Distribution (MusicCast Link)

    public func distributionInfo(host: String) async throws -> YXCDistributionInfo {
        try await get(host, "dist/getDistributionInfo", as: YXCDistributionInfo.self)
    }

    struct ClientInfoBody: Encodable {
        let group_id: String
        let zone: [String]
        let server_ip_address: String?
    }

    struct ServerInfoBody: Encodable {
        let group_id: String
        let type: String?
        let zone: String?
        let client_list: [String]?
    }

    struct GroupNameBody: Encodable { let name: String }

    /// Form a MusicCast Link group: server distributes `zone` to `clientIPs`.
    public func makeGroup(serverHost: String, serverZone: String = "main",
                          clientIPs: [String], groupID: String, name: String? = nil) async throws {
        for client in clientIPs {
            try await post(client, "dist/setClientInfo",
                           body: ClientInfoBody(group_id: groupID, zone: ["main"], server_ip_address: serverHost),
                           as: YXCResponseCode.self)
        }
        try await post(serverHost, "dist/setServerInfo",
                       body: ServerInfoBody(group_id: groupID, type: "add", zone: serverZone, client_list: clientIPs),
                       as: YXCResponseCode.self)
        try await get(serverHost, "dist/startDistribution", ["num": "0"], as: YXCResponseCode.self)
        if let name {
            try await post(serverHost, "dist/setGroupName", body: GroupNameBody(name: name), as: YXCResponseCode.self)
        }
    }

    /// Dissolve any group this server is running and detach the clients.
    public func dissolveGroup(serverHost: String, clientIPs: [String]) async throws {
        try? await get(serverHost, "dist/stopDistribution", as: YXCResponseCode.self)
        try await post(serverHost, "dist/setServerInfo",
                       body: ServerInfoBody(group_id: "", type: nil, zone: nil, client_list: nil),
                       as: YXCResponseCode.self)
        for client in clientIPs {
            try? await post(client, "dist/setClientInfo",
                            body: ClientInfoBody(group_id: "", zone: ["main"], server_ip_address: nil),
                            as: YXCResponseCode.self)
        }
    }

    public static func newGroupID() -> String {
        (0..<32).map { _ in String("0123456789abcdef".randomElement()!) }.joined()
    }
}
