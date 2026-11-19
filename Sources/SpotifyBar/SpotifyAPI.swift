import Foundation

enum APIError: LocalizedError {
    case http(status: Int, message: String, reason: String?)

    var errorDescription: String? {
        switch self {
        case .http(let status, let message, let reason):
            if reason == "PREMIUM_REQUIRED" { return "Spotify Premium is required for playback control." }
            if reason == "NO_ACTIVE_DEVICE" { return "No active device. Open Spotify on any device." }
            if status == 429 { return "Rate limited by Spotify. Try again shortly." }
            return message.isEmpty ? "Spotify error \(status)" : message
        }
    }

    var reason: String? {
        if case .http(_, _, let r) = self { return r }
        return nil
    }
    var status: Int {
        if case .http(let s, _, _) = self { return s }
        return 0
    }
}

@MainActor
final class SpotifyAPI {
    let auth: SpotifyAuth
    private let base = "https://api.spotify.com/v1"
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(auth: SpotifyAuth) { self.auth = auth }

    // MARK: Core

    @discardableResult
    func send(_ method: String, _ path: String, query: [String: String] = [:],
              body: [String: Any]? = nil, retry: Bool = true) async throws -> Data? {
        var comps = URLComponents(string: path.hasPrefix("http") ? path : base + path)!
        if !query.isEmpty {
            comps.queryItems = (comps.queryItems ?? []) + query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("Bearer \(try await auth.validAccessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method != "GET" {
            req.httpBody = Data()
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 && retry {
            try await auth.refresh()
            return try await send(method, path, query: query, body: body, retry: false)
        }
        guard (200..<300).contains(status) else {
            var message = "", reason: String?
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any] {
                message = err["message"] as? String ?? ""
                reason = err["reason"] as? String
            }
            throw APIError.http(status: status, message: message, reason: reason)
        }
        return (status == 204 || data.isEmpty) ? nil : data
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T? {
        guard let data = try await send("GET", path, query: query) else { return nil }
        return try decoder.decode(T.self, from: data)
    }

    /// Follows `next` links until exhausted or `max` items are collected.
    func getAll<T: Codable>(_ path: String, query: [String: String] = [:], max: Int = 200) async throws -> [T] {
        var out: [T] = []
        var page: Paging<T>? = try await get(path, query: query)
        while let p = page {
            out += p.items
            guard out.count < max, let next = p.next else { break }
            page = try await get(next)
        }
        return out
    }

    // MARK: Player

    func playback() async throws -> PlaybackState? {
        try await get("/me/player", query: ["additional_types": "episode"])
    }

    func devices() async throws -> [Device] {
        let r: DevicesResponse? = try await get("/me/player/devices")
        return r?.devices ?? []
    }

    func play(body: [String: Any]?, deviceID: String? = nil) async throws {
        var q: [String: String] = [:]
        if let deviceID { q["device_id"] = deviceID }
        try await send("PUT", "/me/player/play", query: q, body: body)
    }

    func pause() async throws { try await send("PUT", "/me/player/pause") }
    func next() async throws { try await send("POST", "/me/player/next") }
    func previous() async throws { try await send("POST", "/me/player/previous") }

    func seek(_ ms: Int) async throws {
        try await send("PUT", "/me/player/seek", query: ["position_ms": String(ms)])
    }
    func volume(_ pct: Int) async throws {
        try await send("PUT", "/me/player/volume", query: ["volume_percent": String(pct)])
    }
    func shuffle(_ on: Bool) async throws {
        try await send("PUT", "/me/player/shuffle", query: ["state": on ? "true" : "false"])
    }
    func repeatMode(_ mode: String) async throws {
        try await send("PUT", "/me/player/repeat", query: ["state": mode])
    }
    func transfer(to deviceID: String, play: Bool) async throws {
        try await send("PUT", "/me/player", body: ["device_ids": [deviceID], "play": play])
    }

    // MARK: Library

    func playlists() async throws -> [Playlist] {
        let items: [Playlist?] = try await getAll("/me/playlists", query: ["limit": "50"])
        return items.compactMap { $0 }
    }

    func likedTracks() async throws -> [Track] {
        let items: [SavedTrack] = try await getAll("/me/tracks", query: ["limit": "50"], max: 200)
        return items.compactMap(\.track)
    }

    func savedAlbums() async throws -> [Album] {
        let items: [SavedAlbum] = try await getAll("/me/albums", query: ["limit": "50"])
        return items.map(\.album)
    }

    func playlistTracks(_ id: String) async throws -> [Track] {
        let items: [PlaylistEntry] = try await getAll("/playlists/\(id)/items", query: ["limit": "50"], max: 300)
        return items.compactMap(\.item)
    }

    func albumTracks(_ id: String) async throws -> [Track] {
        try await getAll("/albums/\(id)/tracks", query: ["limit": "50"])
    }

    // MARK: Search

    func search(_ q: String) async throws -> SearchResults? {
        try await get("/search", query: ["q": q, "type": "track,artist,album,playlist", "limit": "10"])
    }
}
