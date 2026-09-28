# SkanaTwiee

**English** · [简体中文](README.zh-CN.md)

> **Unofficial.** This app is not affiliated with, endorsed by or connected to
> Twitch Interactive, Inc. "Twitch" is a trademark of Twitch Interactive, Inc.
> The name, the icon and the artwork in this repository are the project's own.

A native HarmonyOS client for Twitch, written in ArkTS: live streams, videos, chat,
downloads and background playback, built directly on system kits (`AVPlayer`,
`AVSession`, ArkWeb, ArkUI) with no third-party runtime dependencies.

Ported from [Xtra for Twitch](https://github.com/andreyasadchy/xtra) (Android) —
that implementation is the reference for every API flow described below.

---

## What it does

**Browse**
- Following: live channels you follow, and their videos
- Search: live channels, videos and users, with recent searches
- Channel page: live status, follower/viewer counts, recent videos, offline banner
- Videos: past broadcasts, highlights and uploads

**Play**
- HLS live streams and VODs through one player, with quality selection
  (Auto / source / 1080p / 720p / 480p / 360p / 160p) and playback speed 0.5×–3×
- Quality is asked for by resolution, so "720p" finds "720p60" and a rendition the
  broadcast does not carry falls back to Auto instead of failing
- Fullscreen, chromeless controls, double-tap seek, playback position memory
- Audio-only playback page for downloaded files, laid out like a music player

**Chat**
- Live chat over Twitch's IRC WebSocket, with emotes from Helix
- VOD comments replayed alongside the video, paged from Twitch's replay API

**Library**
- Favourites and downloads, kept on the device; neither needs an account
- Downloads: pick the rendition, pause and resume, runs under a `dataTransfer`
  background task, plays back offline

**System integration**
- One long-lived `AVSession` per process drives the control-centre card, the
  status-bar capsule and the lock screen (title, channel, cover art, scrubber)
- Background playback under an `audioPlayback` continuous task, with media
  controls from the lock screen, the control centre and headsets

**Language**
- English (default table) and Simplified Chinese (`resources/zh_Hans`)
- Settings → Language: follow the system (default), 简体中文 or English; the app
  restarts itself so the new language is picked up at once

---

## Requirements

| | |
|---|---|
| IDE | DevEco Studio |
| SDK | HarmonyOS 6.1.1 (API 24) or newer — `compatibleSdkVersion` 6.1.1(24), `targetSdkVersion` 26.0.0 |
| Target | Phone or tablet running HarmonyOS |
| Runtime dependencies | none (system kits only) |

Declared permissions: `ohos.permission.INTERNET`, `ohos.permission.GET_NETWORK_INFO`,
`ohos.permission.KEEP_BACKGROUND_RUNNING`. Background modes: `audioPlayback`, `dataTransfer`.

## Build

```shell
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

The HAP lands in `entry/build/default/outputs/default/entry-default-signed.hap`.

**Signing.** `build-profile.json5` names a `default` signing config that points at
certificate files on the machine it was created on. On another machine, generate
your own first — DevEco Studio: *File → Project Structure → Signing Configs →
Automatically generate signature* — otherwise the signing step fails.

## Install

```shell
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

Or just press Run in DevEco Studio with a device or emulator selected.

---

## Project layout

```
AppScope/                      app-level manifest, resources (app name, layered icon)
entry/
  src/main/
    module.json5               abilities, permissions, background modes
    ets/
      common/                  Const (endpoints, pref keys), Prefs, Nav, Immersive, Language
      model/                   plain data types (Video, ChannelInfo, Quality, DownloadEntry, …)
      network/                 Http, GqlClient, Queries, GqlTypes
      pages/                   Index, Player, AudioPlayer, Channel, Library, Login, Settings
      player/                  PlaybackSession (AVSession + continuous task), HlsParser, LiveWindow
      repository/              Auth, Playback, Video, Channel, Download, Favourite,
                               Comment, Settings, SettingsFile, LibraryMigration
      util/                    ImageLoader, TwitchHelper, PagedDataSource, ChatText
      view/                    cards, headers, MenuChoice, SettingRow
    resources/
      base/element/string.json English strings (the default table)
      zh_Hans/element/string.json  Simplified Chinese
      base/media/              layered icon (background + foreground), startIcon
      dark/element/            dark-mode colours
  src/test/                    local unit tests (hypium)
  src/ohosTest/                instrumented tests
scripts/                       icon generator and icon inspector (Swift)
```

## How it works

- **Twitch API** — GraphQL persisted queries for most things, Helix for emote sets,
  and usher for playback tokens and HLS playlists. Following and unfollowing carry the
  Client-Integrity signature Twitch requires.
- **Sign-in** — Twitch's own web sign-in inside a WebView (ArkWeb). The OAuth token and
  the Client-Integrity signature are read off the requests the page makes, so the app
  never handles a password.
- **Playback** — `AVPlayer` with an `XComponent` SURFACE; `player/HlsParser.ets` reads
  the playlist into renditions for the quality menu.
- **Media session** — `player/PlaybackSession.ets` holds one app-level `AVSession`
  refcounted by kind, so a card or capsule cannot be torn down by a page change. Its
  session type follows what is playing (`audio` for the audio-only page, `video`
  otherwise) and it enables `setBackgroundPlayMode(ENABLE_BACKGROUND_PLAY)`, which is
  what makes the system show its own media surface for a *video* session.
- **Local state** — preferences only (`common/Prefs`, keyed in `common/Const.ets`); no
  database. Favourites, downloads, playback positions and the settings live there, and
  the settings file transfer reads and writes the same records.
- **Strings** — every user-visible string is a resource; the language is stored under
  `app_language` and republished to `i18n.System.setAppPreferredLanguage` on each launch.

## Tests and lint

- Local unit tests: `entry/src/test` (hypium) — run a file from DevEco Studio.
- Instrumented tests: `entry/src/ohosTest`.
- Code Linter: rules in `code-linter.json5` (performance, TypeScript and security rule
  sets), run from DevEco Studio.

## Scripts

```shell
swift scripts/gen-icons.swift <output-dir>     # regenerate background/foreground/startIcon
swift scripts/inspect-icon.swift <png> [cols]  # ASCII preview + alpha bounding box
```

`gen-icons.swift` draws the app's mark — a purple field with a pixel-style chat bubble,
a play triangle knocked out of it, a 45° cut on the top-right and a tail on the
bottom-left. Change the constants at the top of the file to alter the colours or the
proportions, then copy the three PNGs into `AppScope/resources/base/media/` and
`entry/src/main/resources/base/media/`.

---

## Known limitations

- **Status-bar capsule / lock screen** come from the media session (`AVSession`), not
  from Live View Kit. `player/LiveWindow.ets` tries Live View Kit as well, but its
  scenarios are task-shaped (delivery, flight, workout…) and each needs a right granted
  by Huawei, so it gives up quietly when the app does not hold one.
- **Video playback is page-bound**: leaving the app (Home, lock screen) keeps playing,
  but navigating away from the player inside the app releases the player. Audio-only
  playback behaves the same way.
- **Downloads stay in the app sandbox** — they are played from the Library, not exported
  to the system file manager or the gallery.

## Credits

- API flows, feature set and UI behaviour follow [Xtra for
  Twitch](https://github.com/andreyasadchy/xtra).
- Built on HarmonyOS system kits: Media Kit, AVSession Kit, ArkWeb, ArkUI, Background
  Tasks Kit, Notification Kit, Localization Kit.

## Licence

GNU Affero General Public License v3.0 — the full text is in [LICENSE](LICENSE).

Xtra for Twitch is licensed under the AGPL-3.0, and this project is a port of it, so
it is under the same licence with the same obligations:

- whoever receives the app is entitled to the corresponding source, under the same
  licence;
- the sources carry prominent notices that this is a modified, ported version and when
  it was changed (the notes in the source files and in `git log` are those notices);
- the software comes with no warranty.

Do not publish a build while keeping the source closed. Publishing under any other
licence would require a clean-room implementation that derives nothing from Xtra's
sources.
