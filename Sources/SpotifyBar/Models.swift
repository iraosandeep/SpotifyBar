import Foundation

struct SpotifyImage: Codable, Hashable {
    let url: String
}

struct Artist: Codable, Hashable, Identifiable {
    let uri: String
    let name: String
    let images: [SpotifyImage]?
    var id: String { uri }
}

struct Album: Codable, Hashable, Identifiable {
    let uri: String
    let name: String
    let images: [SpotifyImage]?
    let artists: [Artist]?
    var id: String { uri }
    var spotifyID: String { uri.components(separatedBy: ":").last ?? "" }
    var artistNames: String { (artists ?? []).map(\.name).joined(separator: ", ") }
}

struct Track: Codable, Hashable, Identifiable {
    let uri: String
    let name: String
    let durationMs: Int?
    let artists: [Artist]?
    let album: Album?
    let images: [SpotifyImage]?   // podcast episodes
    var id: String { uri }
    var artistNames: String { (artists ?? []).map(\.name).joined(separator: ", ") }
    var largeArt: URL? { (album?.images ?? images)?.first.flatMap { URL(string: $0.url) } }
    var smallArt: URL? { (album?.images ?? images)?.last.flatMap { URL(string: $0.url) } }
}

struct Owner: Codable, Hashable {
    let displayName: String?
}

struct Playlist: Codable, Hashable, Identifiable {
    let uri: String
    let name: String
    let images: [SpotifyImage]?
    let owner: Owner?
    var id: String { uri }
    var spotifyID: String { uri.components(separatedBy: ":").last ?? "" }
}

struct Device: Codable, Hashable, Identifiable {
    let id: String?
    let name: String
    let type: String
    let isActive: Bool
    let volumePercent: Int?
    let supportsVolume: Bool?
}

struct DevicesResponse: Codable {
    let devices: [Device]
}

struct PlaybackState: Codable {
    let device: Device?
    let shuffleState: Bool?
    let repeatState: String?
    let progressMs: Int?
    let isPlaying: Bool
    let item: Track?
}

struct Paging<T: Codable>: Codable {
    let items: [T]
    let next: String?
}

struct SavedTrack: Codable { let track: Track? }
struct SavedAlbum: Codable { let album: Album }

/// Playlist entries use `item` (2026 API) but older responses use `track`.
struct PlaylistEntry: Codable {
    let item: Track?
    enum CodingKeys: String, CodingKey { case item, track }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        item = (try? c.decodeIfPresent(Track.self, forKey: .item)) ?? (try? c.decodeIfPresent(Track.self, forKey: .track))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(item, forKey: .item)
    }
}

struct SearchResults: Codable {
    let tracks: Paging<Track?>?
    let artists: Paging<Artist?>?
    let albums: Paging<Album?>?
    let playlists: Paging<Playlist?>?
}

enum DetailTarget: Hashable {
    case playlist(Playlist)
    case album(Album)

    var title: String {
        switch self {
        case .playlist(let p): return p.name
        case .album(let a): return a.name
        }
    }
    var uri: String {
        switch self {
        case .playlist(let p): return p.uri
        case .album(let a): return a.uri
        }
    }
}
