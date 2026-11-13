# Sora — Android

Kotlin app (`app.sora`) with one screen: paste a magnet or URL, `nuvio-engine`
resolves it, ExoPlayer plays the loopback stream.

```
android/
  app/build.gradle.kts        AGP 8.13.2 · Kotlin 2.3.0 · compileSdk 36 · minSdk 24
  app/libs/                   engine-release.aar (+ nuvio-libass-release.aar)
  app/src/main/java/app/sora/MainActivity.kt
  app/src/main/res/layout/activity_main.xml
  app/src/main/res/xml/network_security_config.xml   cleartext for 127.0.0.1 only
  gradlew                     Gradle 8.13 wrapper
```

## Build

From the repository root, on Linux/macOS/WSL2:

```bash
export JAVA_HOME=/path/to/jdk-17
export ANDROID_HOME=$HOME/android-sdk
scripts/build-android.sh --with-libass
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
```

Needs `platforms;android-36`, `ndk;29.0.14206865`, `cmake;4.1.2`, `cmake;3.22.1`.
The engine AAR **cannot** be built on native Windows — see
[`../docs/BUILD.md`](../docs/BUILD.md#android).

## Status

Never compiled. `MainActivity` follows the engine API in
`vendor/nuvio-engine/platform/android/engine/src/main/kotlin/com/nuvio/engine/`,
but the first `assembleDebug` will likely surface small signature mismatches.
`nuvio-libass` is staged by the build script but not yet wired into the player —
see [`../docs/ROADMAP.md`](../docs/ROADMAP.md).

## Notes

- Loopback cleartext is allowed only for `127.0.0.1`/`localhost`.
- `libc++_shared.so` must be supplied by the app when libass is used; the build
  script copies it per ABI.
- No catalogue, no addons: the only input is user-supplied.
