# Roadmap — the work left for Cursor

Sora is a scaffold: the structure, the API usage, and the build paths exist, but
nothing has been compiled on any platform. This file is the ordered TODO list.
Work top to bottom; each milestone ends with something runnable.

## Ground rules

1. **Sora is a player, not a catalogue.** Do not add scrapers, addon manifests,
   streaming-site integrations, or bundled content lists. Input is a magnet or a
   URL the user supplies.
2. **Keep the licence whole.** The app is GPL-3.0 because of `nuvio-engine`.
   Do not add dependencies that forbid relinking or source disclosure.
3. **Verify upstream APIs, do not guess.** The wrappers in `vendor/` are the
   source of truth; this repo was written against them but never compiled.
4. **No invented version numbers.** If a dependency needs bumping, read the
   pinned value from the upstream file first.

## Milestone 0 — first green build (do this before any feature)

### Android

- [ ] Run `scripts/build-android.sh --engine-only` inside WSL2 and record the
      exact error, if any, in `docs/BUILD.md`.
- [ ] Confirm `engine-release.aar` contains `jni/<abi>/libnuvio_engine.so` for
      all four ABIs.
- [ ] Run `scripts/build-android.sh` and fix Kotlin/AGP diagnostics in
      `android/app/src/main/java/app/sora/MainActivity.kt`.
- [ ] Confirm `NuvioEngine.version` exists; if the property has a different name
      in `vendor/nuvio-engine/.../NuvioEngine.kt`, fix the call site.
- [ ] Install the APK and play the Sintel trailer URL from `docs/BUILD.md`.

### iOS

- [ ] Run `scripts/build-apple.sh --build` on macOS; fix Swift diagnostics.
- [ ] Confirm `ios/Vendor/nuvio-engine/platform/apple/NuvioEngine.xcframework`
      is created and linked.
- [ ] Confirm `canImport(NuvioEngine)` is true in the app target, i.e. the
      placeholder branch in `EngineClient.swift` is not what compiles.
- [ ] Play a direct URL in the simulator.
- [ ] Resolve MPVKit: it is declared but unused. Either wire it up (milestone 2)
      or drop the dependency until then so the build stays honest.

### Windows

- [ ] Build the engine package in Docker
      (`scripts\build-windows.ps1 -BuildEngine`).
- [ ] `scripts\build-windows.ps1 -MpvDll <path> -Config Release`; fix MSVC or
      llvm-mingw diagnostics in `windows/src/main.cpp`.
- [ ] Play a direct URL. Then a magnet, verifying `STREAM_PREPARED` carries a
      loopback URL.

**Milestone 0 is done when all three platforms play a direct URL, and Android +
Windows also play a magnet.**

## Milestone 1 — a real player UI

- [ ] File picker: list `NuvioTorrentFile` entries with size and extension, let
      the user choose instead of always taking the largest video.
- [ ] Resume position per file (key on torrent infohash + file index). Persist
      to the platform store; mirror the behaviour of `moviepint/static/js/player.js`
      where sensible.
- [ ] Buffering indicator driven by `currentStreamStats()` /
      `currentStreamStats(_:)` — `contiguousReadyBytes / fileSize` is the number
      to show.
- [ ] Stop the stream when playback ends or the user switches file
      (`stopStream` / `stopStream(_:)`).
- [ ] Error surface: map `NuvioEngineException` / `NuvioEngineError` codes to
      readable Indonesian messages.
- [ ] Android: move to `MediaSessionService` + `media3-ui` controller so
      playback survives rotation and shows a notification.
- [ ] Power/thermal: stop the engine on `onStop` (Android) /
      `scenePhase != .active` (iOS). Keep seeding out of the background.

## Milestone 2 — subtitles

Android first, because `nuvio-libass` is the reason it exists.

- [ ] Stage `nuvio-libass-release.aar` + `libc++_shared.so`
      (`scripts/build-android.sh --with-libass` already does both).
- [ ] Read `vendor/nuvio-libass` docs/sources and wire `AssHandler` /
      `AssVideoEffectAsync` into the ExoPlayer view.
- [ ] Side-load `.srt`/`.ass`/`.vtt` from device storage and from the torrent's
      own subtitle files.
- [ ] iOS/Windows: mpv handles `sub-add` natively; expose a file picker and
      `--sub-file`.

## Milestone 3 — engine integration details

- [ ] Torrent upload policy: default to `Disabled` or `Limited` for mobile data.
      Current config is upstream's `Unlimited`.
- [ ] Disk cache budget: expose a setting; call `reclaimDiskCache()` when the app
      goes idle.
- [ ] `listenPort = 0` is correct; verify the resolved port before building the
      player URL if you ever hardcode one.
- [ ] Multi-file torrents where the largest file is not the video (extras,
      samples). Already mitigated by extension ranking; add a duration probe.
- [ ] Handle `TORRENT_ERROR` explicitly rather than waiting out a timeout
      (Windows `waitForEvent` already special-cases it; port that to Android/iOS
      if the wrappers do not already surface it).

## Milestone 4 — distribution

- [ ] Android release signing config; `isMinifyEnabled` + keep rules for the
      JNI/reflection in the engine AAR (`consumer-rules.pro` ships with it).
- [ ] 16 KB page alignment: NDK 29 is already chosen upstream for Android 15+;
      verify the built `.so` files.
- [ ] iOS: `DEVELOPMENT_TEAM`, app icon, and a decision on App Store
      distribution — GPL-3.0 is incompatible with Apple's usual terms. Direct
      distribution or TestFlight-only is the realistic path.
- [ ] Windows: code signing, and bundle `mpv-2.dll` with its licence text.
- [ ] Resolve the `nuvio-libass` licence gap in `THIRD_PARTY.md` before any
      public Android release.
- [ ] CI: Linux job for the engine AAR, macOS job for the xcframework, Windows
      job for the app. Cache the OpenSSL/libtorrent builds — they dominate.

## Milestone 5 — optional backend

`self-host` (Apache-2.0) gives accounts, watchlist sync, and storage. Wire it
only if you need cross-device resume; the player works without it.

- [ ] `scripts/fetch-deps.sh --with-self-host`, then follow
      `vendor/self-host/docs/self-hosting.md`.
- [ ] Client: store an access token, sync resume positions and favourites.
- [ ] Do not put user magnets or watch history on the server unless the user
      explicitly opts in.

## Known unknowns to check against upstream

These were read from source but not executed. Confirm before trusting them:

| Assumption | Where to check |
|---|---|
| `NuvioEngine.version` is a public constant | `platform/android/.../NuvioEngine.kt` |
| `prepareStream` returns `NuvioStream.url` as `String` / `URL` | `NuvioModels.kt`, `NuvioModels.swift` |
| `NuvioTorrentFile.path` is `/`-separated | `NuvioModels.kt` |
| Event `request_id` matching is sufficient to disambiguate concurrent ops | `src/` event queue |
| `mpv_set_option_string(handle, "wid", "<decimal hwnd>")` is accepted | mpv manual, `--wid` |
| `nuvio_engine.dll` exports the C API listed in `nuvio-engine-windows.def` | the `.def` file |
