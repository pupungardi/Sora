# Build guide

Every version below is read from the upstream build files, not estimated.

## Toolchain matrix

| Component | Version | Source |
|---|---|---|
| JDK | 17 | AGP 8.13 requirement |
| Gradle (engine) | 8.13 | `nuvio-engine/platform/android/gradle/wrapper` |
| Gradle (libass) | 8.11.1 | `nuvio-libass/gradle/wrapper` |
| AGP (engine / libass) | 8.13.2 / 8.7.3 | both `build.gradle.kts` |
| Kotlin (engine / libass) | 2.3.0 / 2.1.10 | both `build.gradle.kts` |
| compileSdk (engine / libass) | 36 / 35 | both `build.gradle.kts` |
| minSdk (engine / libass) | 24 / 21 | both `build.gradle.kts` |
| NDK | `29.0.14206865` | both `build.gradle.kts` |
| CMake (engine / libass) | 4.1.2 / 3.22.1 | both `build.gradle.kts` |
| Media3 | 1.8.0 | libass is `compileOnly` on it |
| iOS deployment target | 16.1 | `platform/apple/Package.swift` |
| MPVKit tag | `0.41.0-n8.1.2-nuvio.5` | `ios/project.yml` |
| CMake (Windows app) | 3.22+ | `windows/CMakeLists.txt` |

## Step 0 — fetch upstream sources

```bash
scripts/fetch-deps.sh                # engine + libass + MPVKit
scripts/fetch-deps.sh --with-self-host
```

`vendor/` is gitignored. Override refs with `NUVIO_ENGINE_REF`,
`NUVIO_LIBASS_REF`, `NUVIO_MPVKIT_REF`, `NUVIO_SELF_HOST_REF`.

## Android

### Host restriction

`nuvio-engine` builds its Android OpenSSL dependency with a script that exits on
anything but Darwin or Linux:

```bash
case "$(uname -s)" in
    Darwin) host_tag=darwin-x86_64 ;;
    Linux)  host_tag=linux-x86_64 ;;
    *) echo "unsupported Android build host" >&2; exit 2 ;;
esac
```

Git Bash on Windows reports `MINGW64_NT…`, so it fails there too. Build the AAR
inside **WSL2 (Ubuntu)**, a Linux container, or macOS. The APK itself can be
built anywhere afterwards.

### SDK packages

```bash
sdkmanager --install \
  "platform-tools" "platforms;android-36" "build-tools;36.0.0" \
  "ndk;29.0.14206865" "cmake;4.1.2" "cmake;3.22.1"
```

`local.properties` is not needed when `ANDROID_HOME` is exported.

### Build

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME=$HOME/android-sdk
scripts/build-android.sh --with-libass
```

Outputs:

```
android/app/libs/engine-release.aar
android/app/libs/nuvio-libass-release.aar         (with --with-libass)
android/app/src/main/jniLibs/<abi>/libc++_shared.so (with --with-libass)
android/app/build/outputs/apk/debug/app-debug.apk
```

The first engine build downloads and compiles OpenSSL 3.5.7 and libtorrent for
four ABIs. Budget tens of minutes, several GB of disk, and a lot of RAM
(`org.gradle.jvmargs=-Xmx4g` is already set).

`--engine-only` skips the APK. Stage AARs manually if you prefer:

```bash
cp vendor/nuvio-engine/platform/android/engine/build/outputs/aar/engine-release.aar \
   android/app/libs/
```

### Why libc++_shared.so is copied

`nuvio-libass`'s Gradle config excludes `**/libc++_shared.so` from its AAR
because upstream assumes the host app already ships one (it was extracted from
mpv-android). An app that only uses libass has to supply it from
`$ANDROID_HOME/ndk/29.0.14206865/toolchains/llvm/prebuilt/<host>/sysroot/usr/lib/<triple>/`.
The build script maps ABI → triple and copies it.

## iOS

macOS only. Requires Xcode 15+, CMake, Ninja, and XcodeGen
(`brew install cmake ninja xcodegen`).

```bash
scripts/build-apple.sh --build      # or --open
```

What happens:

1. `vendor/nuvio-engine/scripts/build-apple-xcframework.sh` builds
   `NuvioEngine.xcframework` (OpenSSL + libtorrent for iOS and macOS slices;
   slow the first time).
2. The engine's Swift package is copied to
   `ios/Vendor/nuvio-engine/platform/apple/` — `ios/project.yml` references it
   as a local package, so this directory must exist before `xcodegen generate`.
3. `xcodegen generate` produces `ios/Sora.xcodeproj`; Swift Package Manager then
   resolves MPVKit at the pinned tag.

Set your team in `ios/project.yml` (`DEVELOPMENT_TEAM`) or in Xcode before
running on a device. `CODE_SIGNING_ALLOWED=NO` is used for the simulator build.

`ios/Vendor/` is gitignored: the xcframework is a build artefact, never commit
it.

## Windows

Two pieces:

1. **Engine package** — cannot be compiled on Windows. Upstream builds it in a
   Linux container with `llvm-mingw`:

   ```bash
   vendor/nuvio-engine/scripts/build-windows-packages.sh   # needs Docker
   ```

   Produces `platform/windows/dist/nuvio-engine-windows-x86_64.zip` containing
   `bin/nuvio_engine.dll`, `lib/libnuvio_engine.dll.a`, `lib/nuvio_engine.def`,
   and `include/nuvio_engine/`.

   `scripts/build-windows.ps1 -BuildEngine` runs that and unpacks the zip to
   `vendor/engine-windows/`.

2. **App** — plain CMake:

   ```powershell
   scripts\build-windows.ps1 -MpvDll C:\tools\mpv\mpv-2.dll -Config Release
   # or by hand:
   cmake -S windows -B windows\build -DNUVIO_ENGINE_DIR=vendor\engine-windows
   cmake --build windows\build --config Release
   ```

   `mpv-2.dll` is not linked; it is loaded with `LoadLibrary`. Put it next to
   `Sora.exe` (or anywhere on `PATH`). Official builds:
   <https://sourceforge.net/projects/mpv-player-windows/files/64bit/>.

   If `NUVIO_ENGINE_DIR` is omitted or its import library is missing, the build
   still succeeds with `SORA_HAS_NUVIO_ENGINE` undefined; magnet support is
   compiled out and only direct URLs play.

MSVC consumers need an import library: `lib /def:nuvio_engine.def /machine:x64`.
The default toolchain upstream uses is `cmake/windows-llvm-mingw-toolchain.cmake`
(llvm-mingw), so Clang/MinGW works out of the box.

## Verifying a build actually works

Play something you are allowed to play:

- **Direct URL** — Sintel or Big Buck Bunny MP4:
  `https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4`
- **Magnet** — a well-seeded public-domain or Creative Commons torrent, e.g.
  the Internet Archive's WebTorrent collections.

Success criteria: metadata arrives, a file is selected, playback starts, seeking
works (that exercises byte ranges), and stopping the player releases the engine.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `unsupported Android build host` | You are on Windows/Git Bash. Use WSL2. |
| `NDK 29.0.14206865 not found` | `sdkmanager "ndk;29.0.14206865"` |
| CMake 4.1.2 vs 3.22.1 conflict | Install both; each module pins its own. |
| `Unable to load class com.android.build.gradle...` | Wrong JDK; use 17. |
| APK builds, black video, `Cleartext HTTP not permitted` | `network_security_config.xml` missing from the manifest. |
| Android `UnsatisfiedLinkError: libc++_shared.so` | libass AAR used without staging the `.so` files. |
| iOS `no such module 'NuvioEngine'` | `ios/Vendor/...` not created; run `scripts/build-apple.sh`. |
| iOS `MPVKit` resolution fails | Tag moved or network blocked; check the pin in `project.yml`. |
| Windows: `mpv-2.dll tidak ditemukan` | Put the DLL next to `Sora.exe`. |
| Windows: magnet says engine unavailable | Build with `-DNUVIO_ENGINE_DIR=…`. |
| Engine returns `BACKEND_UNAVAILABLE` | libtorrent failed to initialise; check the data directory is writable. |
