# SpotifyBar

A tiny, native macOS menu bar app for controlling Spotify. No Dock icon, no window: click the ♪ in your menu bar and you get playback controls, your library and search. It's built with SwiftUI and the official Spotify Web API.

```
 ♪  ← lives here, in the menu bar
┌──────────────────────────────────┐
│ [art]  Song Title                │
│        Artist · Album            │
│ ━━━━━━━━━━●───────────  1:23 3:45│
│   ⤨    ⏮    ▶︎    ⏭    ↻         │
│ 🔈 ━━━━━━━━●──────── 🔊           │
├──────────────────────────────────┤
│   [ Library ]  [ Search ]        │
│  Playlists · Liked Songs · Albums│
│  ...                             │
├──────────────────────────────────┤
│ 💻 MacBook Pro               ⚙︎   │
└──────────────────────────────────┘
```

## Features

- **Now playing**: album art, title, artist, album, and a progress bar you can drag to seek
- **Controls**: play/pause, next, previous, shuffle, repeat (off → all → one), volume
- **Library**: your playlists, Liked Songs, and saved albums. Click to play, or click › to see the tracks and start from any song
- **Search**: songs, artists, albums and playlists as you type
- **Devices**: switch playback between your Mac, phone, speakers, etc.
- **Keyboard**: <kbd>Space</kbd> toggles play/pause while the panel is open
- Light and dark mode, and no Dock icon

## Requirements

| | |
|---|---|
| macOS | 14 Sonoma or newer |
| Spotify | **Premium** account (Spotify requires it for playback control via the API) |
| Build tools | Xcode **or** just the Command Line Tools (`xcode-select --install`) |
| Spotify app | Spotify must be available on at least one device (desktop app, phone, web player, speaker…). SpotifyBar is a remote control; it doesn't play audio itself. |

## Installation

### 1. Install the build tools (skip if you have Xcode)

```bash
xcode-select --install
```

### 2. Get the code and build

```bash
git clone https://github.com/<your-username>/SpotifyBar.git
cd SpotifyBar
./build.sh --install
```

This compiles the app, copies `SpotifyBar.app` into `/Applications` and launches it. A ♪ icon appears in your menu bar.

> Want to build without installing? Run `./build.sh` and the app is placed at `build/SpotifyBar.app`.

### 3. Create your Spotify developer app (one time, ~2 minutes)

SpotifyBar talks to Spotify using **your own** free developer app, so no secrets are shared or bundled.

1. Go to **https://developer.spotify.com/dashboard** and log in with your Spotify account.
2. Click **Create app** and fill in:
   - **App name**: `SpotifyBar` (anything works)
   - **App description**: `Menu bar controller` (anything works)
   - **Redirect URI**: `http://127.0.0.1:8888/callback`, then click **Add**
     > It must be exactly this: `127.0.0.1`, not `localhost`, with port `8888` and path `/callback`.
   - **Which API/SDKs are you planning to use?** tick **Web API**
3. Accept the terms and click **Save**.
4. Open the app's **Settings** and copy the **Client ID**. You do **not** need the Client Secret.

### 4. Log in

1. Click the ♪ icon in the menu bar.
2. Paste the **Client ID** into the field.
3. Click **Log in with Spotify**. Your browser opens; approve the permissions.
4. When the browser says *"SpotifyBar is connected"*, close the tab. You're done 🎉

### 5. (Optional) Start at login

**System Settings → General → Login Items → ＋** and pick `SpotifyBar` from Applications.

## Usage

| Want to… | Do this |
|---|---|
| Play / pause | Click ▶︎ / ⏸ or press <kbd>Space</kbd> |
| Seek | Drag the progress bar |
| Play a playlist / album | Hover its cover and click it, or click the row then **Play** |
| Play a specific song in a playlist | Click › on the playlist, then click the song |
| Search | Switch to **Search** and type |
| Change speaker / device | Click the device name at the bottom-left |
| Log out / quit | ⚙︎ at the bottom-right |

If nothing is playing anywhere, SpotifyBar will automatically pick an available device, or start the Spotify desktop app in the background if it's installed.

## Troubleshooting

| Problem | Fix |
|---|---|
| **`INVALID_CLIENT: Invalid redirect URI`** in the browser | The redirect URI in your Spotify dashboard must be exactly `http://127.0.0.1:8888/callback` |
| **"Spotify Premium is required"** | The Web API only allows playback control for Premium accounts |
| **"No active device"** | Open Spotify on any device (desktop app, phone or open.spotify.com) and try again |
| **403 / "user not registered"** after login | Your developer app is in Development Mode. In the dashboard, open **User Management** and add the Spotify account email you're logging in with |
| Login hangs on "Waiting for browser…" | Another app is using port 8888. Quit it, click **Cancel**, and try again |
| Can't see a playlist's songs | Spotify only returns track lists for playlists you own or collaborate on. You can still play any playlist |
| Search shows only 10 results per type | That's Spotify's current API limit for Development Mode apps |
| "SpotifyBar can't be opened" on another Mac | The app is ad-hoc signed. Right-click → **Open** the first time, or build it on that Mac |

## Uninstall

```bash
pkill -x SpotifyBar
rm -rf /Applications/SpotifyBar.app
rm -rf ~/Library/Application\ Support/SpotifyBar
defaults delete local.spotifybar 2>/dev/null
```

To revoke access completely, also remove the app at https://www.spotify.com/account/apps/.

## Privacy & security

- Login uses **OAuth Authorization Code + PKCE**, so there's no client secret anywhere.
- The OAuth redirect is caught by a one-shot local server bound to `127.0.0.1:8888` that shuts down right after login.
- Tokens are stored only on your Mac at `~/Library/Application Support/SpotifyBar/tokens.json` with `0600` permissions (readable only by you).
- The app talks only to `accounts.spotify.com` and `api.spotify.com`. There's no analytics or tracking.
- Requested scopes: playback state/control, currently playing, private/collaborative playlists (read), library (read).

## Project structure

```
SpotifyBar/
├── Package.swift              # Swift Package (macOS 14+)
├── build.sh                   # builds & bundles SpotifyBar.app (--install to copy to /Applications)
└── Sources/SpotifyBar/
    ├── SpotifyBarApp.swift    # @main, MenuBarExtra, no-Dock activation policy
    ├── Auth.swift             # PKCE login, token refresh/storage, loopback callback server
    ├── SpotifyAPI.swift       # Web API client (player, library, search)
    ├── SpotifyStore.swift     # app state, polling, playback actions, device fallback
    ├── Models.swift           # Codable API models
    ├── Views.swift            # all SwiftUI views
    └── Local.swift            # @State replacement (lets it build with Command Line Tools only)
```

## Development

```bash
swift build                 # debug build
swift run                   # run without bundling (menu bar icon appears)
./build.sh                  # release .app in build/
```

Built against the Spotify Web API including the [February 2026 Development Mode changes](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide), e.g. `/playlists/{id}/items` and a search limit of 10.

## Disclaimer

SpotifyBar is an independent project and is not affiliated with, endorsed by, or sponsored by Spotify. Spotify is a trademark of Spotify AB.
