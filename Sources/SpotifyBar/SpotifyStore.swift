import Foundation
import AppKit

@MainActor
final class SpotifyStore: ObservableObject {
    let api: SpotifyAPI

    // Playback
    @Published var playback: PlaybackState?
    @Published var progressMs: Int = 0
    @Published var devices: [Device] = []

    // Library
    @Published var playlists: [Playlist] = []
    @Published var likedTracks: [Track] = []
    @Published var albums: [Album] = []
    @Published var libraryLoaded = false

    // Detail (playlist / album track list)
    @Published var detail: DetailTarget?
    @Published var detailTracks: [Track] = []
    @Published var detailLoading = false
    @Published var detailNote: String?

    // Search
    @Published var query = ""
    @Published var results: SearchResults?
    @Published var searching = false

    @Published var error: String?

    private var pollTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?

    init(api: SpotifyAPI) { self.api = api }

    var isPlaying: Bool { playback?.isPlaying ?? false }
    var track: Track? { playback?.item }

    // MARK: Polling (only while the panel is open)

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                if tick % 4 == 0 { await self.refreshPlayback() }
                if tick % 40 == 0 { await self.refreshDevices() }
                if self.isPlaying, let d = self.track?.durationMs {
                    self.progressMs = min(self.progressMs + 500, d)
                }
                tick += 1
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshPlayback() async {
        do {
            let p = try await api.playback()
            playback = p
            progressMs = p?.progressMs ?? 0
        } catch {
            if (error as? APIError)?.status != 429 { show(error) }
        }
    }

    func refreshDevices() async {
        devices = (try? await api.devices()) ?? devices
    }

    // MARK: Controls

    func togglePlay() {
        let wasPlaying = isPlaying
        run(refresh: true) { [self] in
            if wasPlaying { try await api.pause() } else { try await playWithDeviceFallback(nil) }
        }
    }

    func next() { run(refresh: true) { [self] in try await api.next() } }
    func previous() { run(refresh: true) { [self] in try await api.previous() } }

    func seek(_ ms: Int) {
        progressMs = ms
        run(refresh: true) { [self] in try await api.seek(ms) }
    }

    func setVolume(_ pct: Int) {
        run(refresh: true) { [self] in try await api.volume(pct) }
    }

    func toggleShuffle() {
        let on = !(playback?.shuffleState ?? false)
        run(refresh: true) { [self] in try await api.shuffle(on) }
    }

    func cycleRepeat() {
        let next: String
        switch playback?.repeatState {
        case "off": next = "context"
        case "context": next = "track"
        default: next = "off"
        }
        run(refresh: true) { [self] in try await api.repeatMode(next) }
    }

    func transfer(to device: Device) {
        guard let id = device.id else { return }
        run(refresh: true) { [self] in
            try await api.transfer(to: id, play: true)
            await refreshDevices()
        }
    }

    // MARK: Playing things

    func playContext(_ uri: String, startAt trackURI: String? = nil) {
        var body: [String: Any] = ["context_uri": uri]
        if let trackURI { body["offset"] = ["uri": trackURI] }
        run(refresh: true) { [self] in try await playWithDeviceFallback(body) }
    }

    func playTracks(_ uris: [String], startAt index: Int = 0) {
        let body: [String: Any] = ["uris": uris, "offset": ["position": index]]
        run(refresh: true) { [self] in try await playWithDeviceFallback(body) }
    }

    func playTrack(_ t: Track) {
        if let album = t.album { playContext(album.uri, startAt: t.uri) } else { playTracks([t.uri]) }
    }

    /// If there's no active device, transfer to an available one, or launch the Spotify app and wait for it.
    private func playWithDeviceFallback(_ body: [String: Any]?) async throws {
        do {
            try await api.play(body: body)
        } catch let e as APIError where e.status == 404 || e.reason == "NO_ACTIVE_DEVICE" {
            var devs = try await api.devices()
            if devs.isEmpty, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = false
                cfg.hides = true
                _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: cfg)
                for _ in 0..<10 where devs.isEmpty {
                    try await Task.sleep(for: .seconds(1))
                    devs = try await api.devices()
                }
            }
            guard let id = (devs.first(where: { $0.type == "Computer" }) ?? devs.first)?.id else {
                throw APIError.http(status: 404, message: "", reason: "NO_ACTIVE_DEVICE")
            }
            try await api.play(body: body, deviceID: id)
            devices = devs
        }
    }

    // MARK: Library

    func loadLibrary(force: Bool = false) async {
        guard force || !libraryLoaded else { return }
        libraryLoaded = true
        async let p = api.playlists()
        async let t = api.likedTracks()
        async let a = api.savedAlbums()
        do { playlists = try await p } catch { show(error) }
        do { likedTracks = try await t } catch { show(error) }
        do { albums = try await a } catch { show(error) }
    }

    func open(_ target: DetailTarget) {
        detail = target
        detailTracks = []
        detailNote = nil
        detailLoading = true
        Task {
            do {
                switch target {
                case .playlist(let p): detailTracks = try await api.playlistTracks(p.spotifyID)
                case .album(let a): detailTracks = try await api.albumTracks(a.spotifyID)
                }
            } catch let e as APIError where e.status == 403 || e.status == 404 {
                detailNote = "Spotify only lists tracks for playlists you own or collaborate on. You can still play it."
            } catch {
                show(error)
            }
            if detail == target { detailLoading = false }
        }
    }

    // MARK: Search (debounced)

    func searchChanged() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = nil; searching = false; return }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                let r = try await api.search(q)
                if !Task.isCancelled { results = r }
            } catch {
                if !Task.isCancelled { show(error) }
            }
            if !Task.isCancelled { searching = false }
        }
    }

    // MARK: Helpers

    func reset() {
        stopPolling()
        playback = nil; devices = []; playlists = []; likedTracks = []; albums = []
        libraryLoaded = false; detail = nil; results = nil; query = ""
    }

    private func run(refresh: Bool, _ op: @escaping () async throws -> Void) {
        Task {
            do {
                try await op()
                if refresh {
                    try? await Task.sleep(for: .milliseconds(350))
                    await refreshPlayback()
                }
            } catch {
                show(error)
            }
        }
    }

    func show(_ error: Error) {
        if error is CancellationError { return }
        if case AuthError.notLoggedIn = error { return }
        self.error = error.localizedDescription
        errorTask?.cancel()
        errorTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self.error = nil }
        }
    }
}
