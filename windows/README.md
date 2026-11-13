# Sora — Windows

Win32 shell. Video goes through libmpv (`mpv-2.dll`, loaded at runtime), magnets
go through the `nuvio-engine` C API (`nuvio_engine.dll`).

```
windows/
  CMakeLists.txt
  src/main.cpp          window, layout, engine polling, mpv embedding
  src/mpv_dynamic.h     the handful of mpv symbols Sora needs
```

## Build

```powershell
# 1. engine package (Docker + Linux containers; cannot be built on Windows)
scripts\build-windows.ps1 -BuildEngine

# 2. app
scripts\build-windows.ps1 -MpvDll C:\tools\mpv\mpv-2.dll -Config Release
```

By hand:

```powershell
cmake -S windows -B windows\build -DNUVIO_ENGINE_DIR=vendor\engine-windows
cmake --build windows\build --config Release
```

Requires CMake 3.22+ and a C++20 compiler (MSVC 2022 or llvm-mingw). No vcpkg,
no NuGet: the only two runtime DLLs are `nuvio_engine.dll` and `mpv-2.dll`, and
both are expected next to `Sora.exe`.

`mpv-2.dll` comes from <https://sourceforge.net/projects/mpv-player-windows/files/64bit/>.

Without `NUVIO_ENGINE_DIR`, the build still succeeds with magnet support
compiled out (`SORA_HAS_NUVIO_ENGINE` undefined); direct URLs keep working.

## Status

Never compiled. Known rough edges for the first pass:

- `waitForEvent()` blocks the UI thread while a magnet resolves. Move it to a
  worker thread and post results back with `PostMessage`.
- The video child is a plain `STATIC` used as an mpv `--wid` host; resize
  handling is only `MoveWindow`, so check for flicker at high DPI.
- Engine event queue overflow is ignored. Add a check on
  `event.dropped_events`.
- No subtitle picker yet; mpv already supports `--sub-file` once you expose it.

## Boundaries

Sora plays what the user supplies. No addons, no catalogue, no scraping.
