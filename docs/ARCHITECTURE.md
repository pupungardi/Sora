# Architecture

Sora is a thin player. Everything hard — torrent protocol, peer selection, piece
scheduling, cache eviction, HTTP range serving — lives in `nuvio-engine`. Each
platform only supplies a window, a video renderer, and a way to show errors.

```
┌───────────────────────────── app (Kotlin / Swift / C++) ─────────────────────────────┐
│  input field ─► resolve(input) ─► player.load(url)                                   │
│                        │                                                             │
│                        ├── magnet:  ─► EngineBridge                                  │
│                        └── http(s): ─► passthrough                                   │
└────────────────────────────────────┬─────────────────────────────────────────────────┘
                                     │
                     ┌───────────────┴───────────────┐
                     │        nuvio-engine           │
                     │  addMagnet → files →          │
                     │  prepareStream → loopback URL │
                     └───────────────┬───────────────┘
                                     │ http://127.0.0.1:<port>/stream/<id>
                     ┌───────────────┴───────────────┐
                     │  ExoPlayer · mpv · MPVKit     │
                     └───────────────────────────────┘
```

## Why the loopback URL

`prepareStream()` starts an HTTP server bound to the loopback interface and
returns a URL for the selected file. That gives the player ordinary
byte-range HTTP semantics: seeking works, the player asks for what it needs, and
the engine prioritises those pieces. No custom data source, no protocol
shim, no shared memory between processes.

Consequences worth remembering:

- **Cleartext must be allowed for localhost.** Android needs
  `network_security_config.xml` (already in `android/app/src/main/res/xml/`);
  iOS needs `NSAllowsLocalNetworking`.
- **The stream dies with the engine.** Call `stopStream()`/`close()` or
  `shutdown()` when leaving the player, or the port and cache stay in use.
- **One file at a time.** Switching episodes means `stopStream()` then
  `prepareStream()` again.

## Per-platform shape

### Android

```
MainActivity
  ├─ NuvioEngine.create(config)        data/cache in filesDir & cacheDir
  ├─ addMagnet → files(torrentId) → prepareStream(...)
  ├─ ExoPlayer.setMediaItem(stream.url)
  └─ nuvio-libass (later) for ASS/SSA
```

`nuvio-engine` ships as an AAR with JNI code for four ABIs. `nuvio-libass` is a
second AAR that intentionally excludes `libc++_shared.so`; the app must provide
it per ABI from the NDK (the build script does this).

### iOS

```
ContentView → PlayerModel → EngineClient (actor)
                              ├─ NuvioEngine Swift package (xcframework)
                              └─ MPVKit (SPM)
```

The engine's Swift package declares the binary target
`NuvioEngine.xcframework`, so no Objective-C bridging header is needed. It
requires iOS 16.1+. The current `PlayerView` uses `AVPlayer` for direct URLs;
swapping in MPVKit is the next step and is isolated to that file.

### Windows

```
Win32 window
  ├─ nuvio_engine.dll   via the C API (include/nuvio_engine/nuvio_engine.h)
  └─ mpv-2.dll          loaded with LoadLibrary, embedded via --wid
```

libmpv is loaded at runtime, not linked, because Windows mpv builds ship only a
DLL. The engine is linked through its import library when
`-DNUVIO_ENGINE_DIR` points at an unpacked package; otherwise magnet support is
compiled out and Sora still plays URLs.

## Event model

`nuvio-engine` is asynchronous at the C level: commands return a `request_id`
and results arrive on an event queue polled with `nuvio_engine_poll_event()`.
The Kotlin and Swift wrappers turn that into `Flow`/`AsyncStream` plus keyed
waits. The Windows shell does the blocking poll itself
(`waitForEvent()` in `windows/src/main.cpp`) — fine for a scaffold, replace it
with a message-pumping loop before shipping.

Events that matter to a player:

| Event | Meaning |
|---|---|
| `TORRENT_METADATA_READY` | magnet resolved, `torrent_id` is usable |
| `TORRENT_ERROR` | failed add/resolve, `message` carries the reason |
| `STREAM_PREPARED` | `stream_url` is ready for the player |
| `STREAM_STOPPED` | loopback stream closed |
| `DISK_CACHE_RECLAIMED` | reclaim finished |

## Data and cache

Both directories must be app-private and writable. Defaults from upstream:

- memory cache 64 MiB, disk cache 2 GiB;
- torrent profile `balanced`;
- listen port `0` (kernel-assigned, avoids collisions);
- stream inactivity timeout 30 s, warm torrent timeout 60 s.

iOS forbids long-lived torrent seeding in the background, and neither store
likes background peer traffic; pause/stop the engine when the app leaves the
foreground. That work is not written yet — see `docs/ROADMAP.md`.

## Trust and safety

- Magnet URIs are length-capped by the engine (16 KiB) and torrent files too
  (4 MiB).
- The loopback server is not exposed to the LAN unless `listenPort`/bind
  configuration is changed upstream.
- Sora never fetches metadata for a torrent the user did not supply.
