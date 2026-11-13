# Sora

A native video player for Android, iOS, and Windows built on the Nuvio stack.

Paste a magnet link or a media URL and Sora plays it. Torrent metadata,
file selection, piece scheduling, caching, and byte-range serving are handled
by [`nuvio-engine`](https://github.com/NuvioMedia/nuvio-engine); the UI and the
video output are platform-native.

```
                ┌──────────────────────────┐
  magnet  ─────►│  nuvio-engine (C++)      │
                │  metadata → files →      │
                │  prepareStream()         │
                └────────────┬─────────────┘
                             │  http://127.0.0.1:<port>/stream/<id>
              ┌──────────────┴───────────────┐
              │                              │
     Android: ExoPlayer + libass      iOS: MPVKit · Windows: libmpv
```

> **Status: scaffold.** Nothing here has been compiled yet — the machine this
> was authored on has no JDK, Android SDK/NDK, CMake, Docker, or Xcode. Every
> build path is written down and the sources follow the upstream APIs, but treat
> the first build as real work, not a formality. See
> [`docs/ROADMAP.md`](docs/ROADMAP.md) for the ordered TODO list.

## Platforms

| Platform | Engine | Video output | Subtitles | Build host |
|---|---|---|---|---|
| Android | `nuvio-engine` AAR (JNI) | Media3 / ExoPlayer | `nuvio-libass` (ASS/SSA) | Linux, macOS, WSL2 |
| iOS | `NuvioEngine.xcframework` | [MPVKit](https://github.com/NuvioMedia/MPVKit) | mpv | macOS only |
| Windows | `nuvio_engine.dll` (C API) | libmpv (`mpv-2.dll`) | mpv | Windows, or any host with CMake |

`MPVKit` is Apple-only and `nuvio-libass` is Android-only, so no single build
links both. The engine is shared by all three.

## Layout

```
android/                Gradle app: app.sora
  app/src/main/java/app/sora/MainActivity.kt
  app/libs/             <- engine-release.aar (and nuvio-libass-release.aar)
ios/                    XcodeGen spec + SwiftUI sources
  project.yml           MPVKit SPM pin + local NuvioEngine package
  Sources/Sora/
  Vendor/               <- engine Swift package, created by the build script
windows/                CMake + Win32 shell
  CMakeLists.txt
  src/main.cpp          libmpv via LoadLibrary, engine via its C API
scripts/                fetch-deps, build-android, build-apple, build-windows
docs/                   ARCHITECTURE.md, BUILD.md, ROADMAP.md
vendor/                 cloned upstream sources (ignored by git)
```

## Quick start

```bash
# 1. fetch the upstream Nuvio sources (engine + libass + MPVKit)
scripts/fetch-deps.sh

# 2a. Android — on Linux, macOS, or WSL2 (not Git Bash on Windows)
export JAVA_HOME=/path/to/jdk-17
export ANDROID_HOME=$HOME/android-sdk
scripts/build-android.sh --with-libass

# 2b. iOS — on macOS
scripts/build-apple.sh --build

# 2c. Windows — in PowerShell
scripts\build-windows.ps1 -BuildEngine -MpvDll C:\tools\mpv\mpv-2.dll
```

Exact SDK/NDK/CMake versions and the known blockers are in
[`docs/BUILD.md`](docs/BUILD.md). Read the "why the engine cannot be built on
Windows" section before filing a build bug.

## What Sora is not

Sora is a player, not a catalogue. There is no addon system, no scraper, no
index of copyrighted films, and no bundled source list. The only input is a
magnet link or a URL that the user already owns or is licensed to watch —
public-domain films, Creative Commons releases, or their own files.

Nothing in this repository talks to Stremio/Torrentio, embedwave, IDLIX, or any
similar service. Please keep it that way when extending it.

## Licence

Sora links `nuvio-engine`, which is **GPL-3.0-or-later**, so Sora itself is
distributed under the **GNU General Public License v3.0** — see
[`LICENSE`](LICENSE). If you ship a binary, you must also publish the complete
corresponding source.

Per-dependency terms, including the `nuvio-libass` licence gap that must be
resolved before distributing an Android build, are in
[`THIRD_PARTY.md`](THIRD_PARTY.md).
