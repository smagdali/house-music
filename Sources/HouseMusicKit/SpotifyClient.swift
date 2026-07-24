import Foundation
import CryptoKit

/// Spotify Web API client with PKCE auth. No client secret anywhere.
public actor SpotifyClient {
    public static let clientID = "5a444101070b4b4983069d17237b30b3"
    public static let redirectURI = "housemusic://spotify-callback"
    public static let scopes = "user-read-playback-state user-modify-playback-state"

    let session: URLSession
    let tokenStore: SpotifyTokenStore

    public init(session: URLSession = .shared, tokenStore: SpotifyTokenStore = KeychainTokenStore()) {
        self.session = session
        self.tokenStore = tokenStore
    }

    // MARK: - PKCE

    public struct AuthRequest: Sendable {
        public let url: URL
        public let codeVerifier: String
    }

    public static func makeAuthRequest() -> AuthRequest {
        let verifier = randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: scopes),
        ]
        return AuthRequest(url: comps.url!, codeVerifier: verifier)
    }

    static func randomURLSafe(_ count: Int) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<count).map { _ in chars.randomElement()! })
    }

    public struct Token: Codable, Sendable {
        public var accessToken: String
        public var refreshToken: String
        public var expiresAt: Date

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
        }
    }

    struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    public func exchangeCode(_ code: String, verifier: String) async throws {
        let token = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": Self.clientID,
            "code_verifier": verifier,
        ], existingRefresh: nil)
        try tokenStore.save(token)
    }

    func validToken() async throws -> Token {
        guard var token = tokenStore.load() else {
            throw HouseMusicError.notConfigured("Spotify login")
        }
        if token.expiresAt.timeIntervalSinceNow < 60 {
            token = try await tokenRequest([
                "grant_type": "refresh_token",
                "refresh_token": token.refreshToken,
                "client_id": Self.clientID,
            ], existingRefresh: token.refreshToken)
            try tokenStore.save(token)
        }
        return token
    }

    func tokenRequest(_ form: [String: String], existingRefresh: String?) async throws -> Token {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Token(accessToken: decoded.access_token,
                     refreshToken: decoded.refresh_token ?? existingRefresh ?? "",
                     expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in)))
    }

    // MARK: - Player

    public struct ConnectDevice: Decodable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let isActive: Bool

        enum CodingKeys: String, CodingKey {
            case id, name
            case isActive = "is_active"
        }
    }

    struct DevicesResponse: Decodable { let devices: [ConnectDevice] }

    func api(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        let token = try await validToken()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1" + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, _) = try await session.data(for: request)
        return data
    }

    public func devices() async throws -> [ConnectDevice] {
        let data = try await api("GET", "/me/player/devices")
        return try JSONDecoder().decode(DevicesResponse.self, from: data).devices
    }

    /// Transfer the user's active session to the Connect device whose name
    /// matches (the Yamahas advertise their room names; a MusicCast group is
    /// advertised by its master).
    public func transferPlayback(toDeviceNamed name: String, play: Bool) async throws {
        let all = try await devices()
        guard let target = all.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) else {
            throw HouseMusicError.notConfigured("Spotify Connect device \(name)")
        }
        let body = try JSONSerialization.data(withJSONObject: ["device_ids": [target.id], "play": play])
        _ = try await api("PUT", "/me/player", body: body)
    }

    public func pause() async throws { _ = try await api("PUT", "/me/player/pause") }
    public func play() async throws { _ = try await api("PUT", "/me/player/play") }

    public var isLoggedIn: Bool { tokenStore.load() != nil }

    public func logout() { tokenStore.clear() }
}

// MARK: - Token storage

public protocol SpotifyTokenStore: Sendable {
    func load() -> SpotifyClient.Token?
    func save(_ token: SpotifyClient.Token) throws
    func clear()
}

/// Keychain-backed store; per-device (each family member logs in on their own phone).
public struct KeychainTokenStore: SpotifyTokenStore {
    static let service = "org.whitelabel.housemusic.spotify"

    public init() {}

    public func load() -> SpotifyClient.Token? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyClient.Token.self, from: data)
    }

    public func save(_ token: SpotifyClient.Token) throws {
        let data = try JSONEncoder().encode(token)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// In-memory store for tests.
public final class MemoryTokenStore: SpotifyTokenStore, @unchecked Sendable {
    private var token: SpotifyClient.Token?
    public init() {}
    public func load() -> SpotifyClient.Token? { token }
    public func save(_ token: SpotifyClient.Token) throws { self.token = token }
    public func clear() { token = nil }
}
