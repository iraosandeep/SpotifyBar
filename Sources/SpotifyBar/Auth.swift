import Foundation
import AppKit
import CryptoKit
import Network

struct Tokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum AuthError: LocalizedError {
    case missingClientID, stateMismatch, denied(String), tokenFailed(String), notLoggedIn

    var errorDescription: String? {
        switch self {
        case .missingClientID: return "Enter your Spotify Client ID first."
        case .stateMismatch: return "Login failed (state mismatch). Try again."
        case .denied(let e): return "Login was cancelled: \(e)"
        case .tokenFailed(let e): return "Token request failed: \(e)"
        case .notLoggedIn: return "Not logged in."
        }
    }
}

@MainActor
final class SpotifyAuth: ObservableObject {
    static let port: UInt16 = 8888
    static let redirectURI = "http://127.0.0.1:8888/callback"
    static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-library-read",
    ].joined(separator: " ")

    @Published var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: "clientID") }
    }
    @Published private(set) var tokens: Tokens?
    var isLoggedIn: Bool { tokens != nil }

    private var server: CallbackServer?
    private var refreshTask: Task<Tokens, Error>?

    init() {
        clientID = UserDefaults.standard.string(forKey: "clientID") ?? ""
        tokens = TokenStore.load()
    }

    // MARK: Login (Authorization Code + PKCE)

    func login() async throws {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw AuthError.missingClientID }

        let verifier = PKCE.makeVerifier()
        let state = UUID().uuidString
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: id),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            .init(name: "scope", value: Self.scopes),
            .init(name: "state", value: state),
        ]
        let authURL = comps.url!

        server?.cancel()
        let server = CallbackServer()
        self.server = server
        let callback = try await server.waitForCallback(port: Self.port) {
            NSWorkspace.shared.open(authURL)
        }
        self.server = nil
        NSApp.activate(ignoringOtherApps: true)

        let query = Dictionary(uniqueKeysWithValues: (callback.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let err = query["error"] { throw AuthError.denied(err) }
        guard query["state"] == state else { throw AuthError.stateMismatch }
        guard let code = query["code"] else { throw AuthError.denied("no code returned") }

        let t = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": id,
            "code_verifier": verifier,
        ], previousRefresh: nil)
        setTokens(t)
    }

    func cancelLogin() {
        server?.cancel()
        server = nil
    }

    func logout() {
        refreshTask?.cancel()
        refreshTask = nil
        tokens = nil
        TokenStore.clear()
    }

    // MARK: Tokens

    func validAccessToken() async throws -> String {
        guard let t = tokens else { throw AuthError.notLoggedIn }
        if t.expiresAt > Date().addingTimeInterval(60) { return t.accessToken }
        return try await refresh().accessToken
    }

    @discardableResult
    func refresh() async throws -> Tokens {
        if let task = refreshTask { return try await task.value }
        guard let t = tokens else { throw AuthError.notLoggedIn }
        let task = Task { () throws -> Tokens in
            try await tokenRequest([
                "grant_type": "refresh_token",
                "refresh_token": t.refreshToken,
                "client_id": clientID,
            ], previousRefresh: t.refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let new = try await task.value
            setTokens(new)
            return new
        } catch AuthError.tokenFailed(let msg) where msg.contains("invalid_grant") {
            logout()   // refresh token revoked -> force re-login
            throw AuthError.notLoggedIn
        }
    }

    private func setTokens(_ t: Tokens) {
        tokens = t
        TokenStore.save(t)
    }

    private func tokenRequest(_ params: [String: String], previousRefresh: String?) async throws -> Tokens {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params.map { "\($0.key)=\(formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.tokenFailed(String(data: data, encoding: .utf8) ?? "unknown error")
        }
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        guard let refresh = r.refresh_token ?? previousRefresh else {
            throw AuthError.tokenFailed("no refresh token")
        }
        return Tokens(accessToken: r.access_token, refreshToken: refresh,
                      expiresAt: Date().addingTimeInterval(r.expires_in))
    }

    private func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

// MARK: - PKCE

enum PKCE {
    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64url(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64url(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Token persistence (file in Application Support, owner read/write only)

enum TokenStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpotifyBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("tokens.json")
    }

    static func load() -> Tokens? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Tokens.self, from: data)
    }

    static func save(_ t: Tokens) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(t) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Loopback callback server

/// Tiny one-shot HTTP server on 127.0.0.1 that captures the OAuth redirect.
final class CallbackServer {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URLComponents, Error>?

    func waitForCallback(port: UInt16, onReady: @escaping () -> Void) async throws -> URLComponents {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
                let listener = try NWListener(using: params)
                self.listener = listener

                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready: onReady()
                    case .failed(let err): self?.finish(.failure(err))
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] conn in
                    conn.start(queue: .main)
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                        guard let data, let text = String(data: data, encoding: .utf8),
                              let line = text.components(separatedBy: "\r\n").first else {
                            conn.cancel(); return
                        }
                        let parts = line.split(separator: " ")
                        guard parts.count >= 2,
                              let comps = URLComponents(string: "http://127.0.0.1" + parts[1]),
                              comps.path == "/callback" else {
                            Self.respond(conn, status: "404 Not Found", body: "Not found")
                            return
                        }
                        Self.respond(conn, status: "200 OK", body: """
                        <html><body style="font-family:-apple-system;text-align:center;padding-top:80px">
                        <h2>SpotifyBar is connected</h2><p>You can close this tab.</p></body></html>
                        """)
                        self?.finish(.success(comps))
                    }
                }
                listener.start(queue: .main)
            } catch {
                finish(.failure(error))
            }
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<URLComponents, Error>) {
        listener?.cancel()
        listener = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    private static func respond(_ conn: NWConnection, status: String, body: String) {
        let bytes = Data(body.utf8)
        var resp = Data("HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n".utf8)
        resp.append(bytes)
        conn.send(content: resp, completion: .contentProcessed { _ in conn.cancel() })
    }
}
