import SwiftUI
import AppKit

private let spotifyGreen = Color(red: 0.11, green: 0.73, blue: 0.33)

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var auth: SpotifyAuth
    @EnvironmentObject var store: SpotifyStore

    var body: some View {
        Group {
            if auth.isLoggedIn { MainView() } else { LoginView() }
        }
        .frame(width: 360, height: 580)
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            if !loggedIn { store.reset() }
        }
    }
}

// MARK: - Login

struct LoginView: View {
    @EnvironmentObject var auth: SpotifyAuth
    @Local private var busy = false
    @Local private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "music.note").font(.title2).foregroundStyle(spotifyGreen)
                Text("SpotifyBar").font(.title2.bold())
            }
            Text("One-time setup").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Create an app at developer.spotify.com/dashboard")
                Text("2. Add this Redirect URI and select **Web API**:")
                HStack {
                    Text(SpotifyAuth.redirectURI).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SpotifyAuth.redirectURI, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                }
                Text("3. Paste the app's Client ID below")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Link("Open Spotify Dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                .font(.callout)

            TextField("Client ID", text: $auth.clientID)
                .textFieldStyle(.roundedBorder)

            Button {
                busy = true; error = nil
                Task {
                    do { try await auth.login() } catch is CancellationError {} catch { self.error = error.localizedDescription }
                    busy = false
                }
            } label: {
                HStack {
                    if busy { ProgressView().controlSize(.small) }
                    Text(busy ? "Waiting for browser…" : "Log in with Spotify")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(spotifyGreen)
            .controlSize(.large)
            .disabled(busy || auth.clientID.trimmingCharacters(in: .whitespaces).isEmpty)

            if busy {
                Button("Cancel") { auth.cancelLogin() }.buttonStyle(.borderless)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer()
            HStack {
                Text("Playback control requires Spotify Premium.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
        }
        .padding(18)
    }
}

// MARK: - Main

enum Tab: String, CaseIterable { case library = "Library", search = "Search" }

struct MainView: View {
    @EnvironmentObject var store: SpotifyStore
    @Local private var tab: Tab = .library

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingView()
                .padding(14)
            Divider()

            if let detail = store.detail {
                DetailView(target: detail)
            } else {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                switch tab {
                case .library: LibraryView()
                case .search: SearchView()
                }
            }

            if let err = store.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.85))
            }
            Divider()
            FooterView()
        }
        .onAppear {
            store.startPolling()
            Task { await store.loadLibrary() }
        }
        .onDisappear { store.stopPolling() }
    }
}

// MARK: - Now Playing

struct NowPlayingView: View {
    @EnvironmentObject var store: SpotifyStore
    @Local private var seeking = false
    @Local private var seekValue: Double = 0
    @Local private var adjustingVolume = false
    @Local private var volumeValue: Double = 50

    var body: some View {
        let track = store.track
        let duration = Double(track?.durationMs ?? 1)

        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Artwork(url: track?.largeArt, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track?.name ?? "Nothing playing")
                        .font(.headline).lineLimit(1)
                    Text(track?.artistNames.isEmpty == false ? track!.artistNames : (track?.album?.name ?? "Pick something from your library"))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    if let album = track?.album?.name, !(track?.artistNames.isEmpty ?? true) {
                        Text(album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { seeking ? seekValue : Double(store.progressMs) },
                        set: { seekValue = $0 }
                    ),
                    in: 0...max(duration, 1),
                    onEditingChanged: { editing in
                        if editing { seekValue = Double(store.progressMs); seeking = true }
                        else { seeking = false; store.seek(Int(seekValue)) }
                    }
                )
                .controlSize(.mini)
                .tint(spotifyGreen)
                .disabled(track == nil)
                HStack {
                    Text(timeString(seeking ? Int(seekValue) : store.progressMs))
                    Spacer()
                    Text(timeString(track?.durationMs ?? 0))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 22) {
                ControlButton(icon: "shuffle", active: store.playback?.shuffleState == true) { store.toggleShuffle() }
                ControlButton(icon: "backward.fill") { store.previous() }
                Button { store.togglePlay() } label: {
                    Image(systemName: store.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(spotifyGreen)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                ControlButton(icon: "forward.fill") { store.next() }
                ControlButton(icon: store.playback?.repeatState == "track" ? "repeat.1" : "repeat",
                              active: (store.playback?.repeatState ?? "off") != "off") { store.cycleRepeat() }
            }

            if store.playback?.device?.supportsVolume != false {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { adjustingVolume ? volumeValue : Double(store.playback?.device?.volumePercent ?? 50) },
                            set: { volumeValue = $0 }
                        ),
                        in: 0...100,
                        onEditingChanged: { editing in
                            if editing { volumeValue = Double(store.playback?.device?.volumePercent ?? 50); adjustingVolume = true }
                            else { adjustingVolume = false; store.setVolume(Int(volumeValue)) }
                        }
                    )
                    .controlSize(.mini)
                    Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
                }
                .disabled(store.playback == nil)
            }
        }
    }

    private func timeString(_ ms: Int) -> String {
        let s = max(ms, 0) / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct ControlButton: View {
    let icon: String
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? spotifyGreen : .primary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Library

enum LibrarySection: String, CaseIterable { case playlists = "Playlists", liked = "Liked Songs", albums = "Albums" }

struct LibraryView: View {
    @EnvironmentObject var store: SpotifyStore
    @Local private var section: LibrarySection = .playlists

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(LibrarySection.allCases, id: \.self) { s in
                    Button(s.rawValue) { section = s }
                        .buttonStyle(ChipStyle(selected: section == s))
                }
                Spacer()
                Button { Task { await store.loadLibrary(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh library")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 0) {
                    switch section {
                    case .playlists:
                        ForEach(store.playlists) { p in
                            MediaRow(title: p.name, subtitle: p.owner?.displayName ?? "Playlist",
                                     art: p.images?.last.flatMap { URL(string: $0.url) },
                                     onPlay: { store.playContext(p.uri) },
                                     onOpen: { store.open(.playlist(p)) })
                        }
                    case .liked:
                        let uris = store.likedTracks.map(\.uri)
                        ForEach(Array(store.likedTracks.enumerated()), id: \.element.id) { i, t in
                            MediaRow(title: t.name, subtitle: t.artistNames, art: t.smallArt,
                                     highlighted: store.track?.uri == t.uri,
                                     onPlay: { store.playTracks(uris, startAt: i) })
                        }
                    case .albums:
                        ForEach(store.albums) { a in
                            MediaRow(title: a.name, subtitle: a.artistNames,
                                     art: a.images?.last.flatMap { URL(string: $0.url) },
                                     onPlay: { store.playContext(a.uri) },
                                     onOpen: { store.open(.album(a)) })
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
        }
    }
}

// MARK: - Detail (playlist / album tracks)

struct DetailView: View {
    @EnvironmentObject var store: SpotifyStore
    let target: DetailTarget

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { store.detail = nil } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                Text(target.title).font(.headline).lineLimit(1)
                Spacer()
                Button { store.playContext(target.uri) } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(spotifyGreen)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if store.detailLoading {
                ProgressView().padding().frame(maxHeight: .infinity)
            } else if let note = store.detailNote {
                Text(note).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding().frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.detailTracks.enumerated()), id: \.offset) { _, t in
                            MediaRow(title: t.name, subtitle: t.artistNames, art: t.smallArt,
                                     highlighted: store.track?.uri == t.uri,
                                     onPlay: { store.playContext(target.uri, startAt: t.uri) })
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
    }
}

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject var store: SpotifyStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Songs, artists, albums, playlists", text: $store.query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onChange(of: store.query) { _, _ in store.searchChanged() }
                if store.searching { ProgressView().controlSize(.small) }
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .onAppear { focused = true }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let r = store.results {
                        let tracks = r.tracks?.items.compactMap { $0 } ?? []
                        let artists = r.artists?.items.compactMap { $0 } ?? []
                        let albums = r.albums?.items.compactMap { $0 } ?? []
                        let playlists = r.playlists?.items.compactMap { $0 } ?? []

                        if !tracks.isEmpty {
                            SectionHeader("Songs")
                            ForEach(tracks) { t in
                                MediaRow(title: t.name, subtitle: t.artistNames, art: t.smallArt,
                                         highlighted: store.track?.uri == t.uri,
                                         onPlay: { store.playTrack(t) })
                            }
                        }
                        if !artists.isEmpty {
                            SectionHeader("Artists")
                            ForEach(artists) { a in
                                MediaRow(title: a.name, subtitle: "Artist",
                                         art: a.images?.last.flatMap { URL(string: $0.url) }, round: true,
                                         onPlay: { store.playContext(a.uri) })
                            }
                        }
                        if !albums.isEmpty {
                            SectionHeader("Albums")
                            ForEach(albums) { a in
                                MediaRow(title: a.name, subtitle: a.artistNames,
                                         art: a.images?.last.flatMap { URL(string: $0.url) },
                                         onPlay: { store.playContext(a.uri) },
                                         onOpen: { store.open(.album(a)) })
                            }
                        }
                        if !playlists.isEmpty {
                            SectionHeader("Playlists")
                            ForEach(playlists) { p in
                                MediaRow(title: p.name, subtitle: p.owner?.displayName ?? "Playlist",
                                         art: p.images?.last.flatMap { URL(string: $0.url) },
                                         onPlay: { store.playContext(p.uri) },
                                         onOpen: { store.open(.playlist(p)) })
                            }
                        }
                    } else if store.query.isEmpty {
                        Text("Search Spotify").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 6)
            }
        }
    }
}

struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption.bold()).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 2)
    }
}

// MARK: - Footer

struct FooterView: View {
    @EnvironmentObject var store: SpotifyStore
    @EnvironmentObject var auth: SpotifyAuth

    var body: some View {
        HStack {
            Menu {
                if store.devices.isEmpty {
                    Text("No devices found — open Spotify somewhere")
                }
                ForEach(store.devices) { d in
                    Button {
                        store.transfer(to: d)
                    } label: {
                        if d.isActive { Label(d.name, systemImage: "checkmark") } else { Text(d.name) }
                    }
                }
                Divider()
                Button("Refresh devices") { Task { await store.refreshDevices() } }
            } label: {
                Label(store.playback?.device?.name ?? "Devices", systemImage: deviceIcon(store.playback?.device?.type))
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Menu {
                Button("Open Spotify") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    } else {
                        NSWorkspace.shared.open(URL(string: "https://open.spotify.com")!)
                    }
                }
                Divider()
                Button("Log out") { auth.logout() }
                Button("Quit SpotifyBar") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func deviceIcon(_ type: String?) -> String {
        switch type?.lowercased() {
        case "smartphone": return "iphone"
        case "speaker": return "hifispeaker"
        case "tv": return "tv"
        case "tablet": return "ipad"
        default: return "laptopcomputer"
        }
    }
}

// MARK: - Reusable

struct MediaRow: View {
    let title: String
    let subtitle: String
    let art: URL?
    var round = false
    var highlighted = false
    let onPlay: () -> Void
    var onOpen: (() -> Void)? = nil
    @Local private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Artwork(url: art, size: 36, round: round)
                if hovering {
                    Image(systemName: "play.fill").font(.caption).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: round ? 18 : 4))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onPlay)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout).lineLimit(1)
                    .foregroundStyle(highlighted ? spotifyGreen : .primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let onOpen {
                Button(action: onOpen) { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless)
                    .help("Show tracks")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.07) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { (onOpen ?? onPlay)() }
    }
}

struct Artwork: View {
    let url: URL?
    let size: CGFloat
    var round = false

    var body: some View {
        AsyncImage(url: url) { img in
            img.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Color.primary.opacity(0.08)
                Image(systemName: "music.note").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: round ? size / 2 : 4))
    }
}

struct ChipStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(selected ? Color.primary.opacity(0.85) : Color.primary.opacity(0.08)))
            .foregroundStyle(selected ? Color(nsColor: .windowBackgroundColor) : .primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
