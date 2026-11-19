import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct SpotifyBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var auth: SpotifyAuth
    @StateObject private var store: SpotifyStore

    init() {
        let auth = SpotifyAuth()
        _auth = StateObject(wrappedValue: auth)
        _store = StateObject(wrappedValue: SpotifyStore(api: SpotifyAPI(auth: auth)))
    }

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(auth)
                .environmentObject(store)
        } label: {
            Image(systemName: store.isPlaying ? "music.note" : "music.note.list")
        }
        .menuBarExtraStyle(.window)
    }
}
