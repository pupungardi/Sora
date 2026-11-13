# Prompt untuk Cursor AI

Dua file, dua fungsi:

| File | Fungsi |
|---|---|
| `PROMPT_CURSOR.md` (file ini) | prompt yang kamu **paste** ke Cursor Composer / Agent |
| `.cursor/rules/sora.mdc` | aturan yang Cursor **baca otomatis** setiap sesi |

Kalau Cursor Agent sudah membuka repo ini, cukup pakai versi pendek di bawah.
Versi lengkap dipakai kalau kamu mulai dari chat kosong atau mau Cursor
mengerjakan satu milestone secara utuh.

---

## Versi pendek (copy-paste)

```text
Kamu bekerja di repo Sora (https://github.com/pupungardi/Sora): pemutar video
native Android/iOS/Windows di atas Nuvio stack. Baca README.md, docs/ARCHITECTURE.md,
docs/BUILD.md, docs/ROADMAP.md, dan THIRD_PARTY.md sebelum menulis kode.

Kerjakan docs/ROADMAP.md Milestone 0 secara berurutan: Android dulu, lalu Windows,
lalu iOS. Untuk setiap langkah: jalankan perintah build yang ada, perbaiki error
yang muncul, dan jangan mengklaim build hijau tanpa output perintah yang mendukung.

Aturan keras:
- Sora adalah pemutar, bukan katalog. Jangan tambah scraper, addon Stremio,
  integrasi situs streaming, atau daftar film. Input hanya magnet/URL dari pengguna.
- Jangan menambah dependensi yang melarang relink/source disclosure (app ini GPL-3.0
  karena nuvio-engine).
- Jangan commit vendor/, build output, AAR, xcframework, atau DLL.
- Jangan mengubah versi toolchain tanpa membaca file upstream yang menetapkannya.
- Jangan menyentuh repo MoviePint web; fokus di direktori Sora ini saja.

Kalau toolchain tidak tersedia di mesin ini, jangan berpura-pura: catat apa yang
hilang, kerjakan bagian yang bisa diverifikasi (mis. review signature API terhadap
vendor/, validasi konfigurasi Gradle/CMake/XcodeGen), lalu lanjut ke platform lain.

Laporkan tiap iterasi dalam format: (1) apa yang berubah dan kenapa, (2) perintah
yang dijalankan beserta hasil ringkasnya, (3) error yang masih tersisa, (4) langkah
berikutnya.
```

---

## Versi lengkap (copy-paste)

```text
# Peran

Kamu adalah engineer yang melanjutkan repo Sora — aplikasi pemutar video native
untuk Android, iOS, dan Windows, dibangun di atas tiga repo Nuvio:

  nuvio-engine   inti torrent + streaming (GPL-3.0-or-later, dipakai ketiga platform)
  nuvio-libass   render subtitle ASS/SSA untuk Android (ExoPlayer)
  MPVKit         libmpv untuk Apple (iOS/macOS), hanya dipakai di target iOS

Repo ini scaffold, belum pernah dikompilasi di platform mana pun. Tugasmu membuat
build pertama benar-benar hijau, lalu melangkah ke fitur sesuai docs/ROADMAP.md.

# Baca dulu, baru menulis kode

Wajib dibaca sebelum perubahan pertama:

  README.md              gambaran, matriks platform, batas konten
  docs/ARCHITECTURE.md   alur magnet -> loopback URL -> player, model event, cache
  docs/BUILD.md          versi toolchain eksak + blocker per host + troubleshooting
  docs/ROADMAP.md        urutan pekerjaan; Milestone 0 adalah target pertamamu
  THIRD_PARTY.md         lisensi dan celah lisensi nuvio-libass

Sumber kebenaran API adalah vendor/ (hasil scripts/fetch-deps.sh), bukan tebakan
dan bukan ingatanmu:

  vendor/nuvio-engine/include/nuvio_engine/nuvio_engine.h          C API (Windows)
  vendor/nuvio-engine/platform/android/engine/src/main/kotlin/...  API Kotlin
  vendor/nuvio-engine/platform/apple/Sources/NuvioEngine/...       API Swift

Kalau signature di repo ini berbeda dengan vendor/, vendor/ yang benar: perbaiki
pemanggilnya, jangan mengubah vendor/.

# Kondisi lingkungan (penting)

- nuvio-engine hanya bisa dibangun untuk Android di Darwin/Linux. Skripnya menolak
  host lain, termasuk Git Bash (MINGW64). Di Windows: pakai WSL2 atau CI Linux.
- Paket Windows nuvio-engine dibangun lewat Docker (scripts/build-windows.ps1
  -BuildEngine), bukan kompilasi native Windows.
- iOS butuh macOS + Xcode + xcodegen. Tidak ada jalan lain.
- Kalau alat yang dibutuhkan tidak ada di mesin ini: jangan mengklaim sukses, jangan
  menulis output palsu. Catat kebutuhan alatnya, kerjakan bagian yang tetap bisa
  diverifikasi, dan lanjut.

# Urutan kerja

Milestone 0 — build pertama hijau (detail di docs/ROADMAP.md):

1. Android (WSL2/Linux/macOS)
   - scripts/fetch-deps.sh kalau vendor/ kosong
   - scripts/build-android.sh --engine-only, lalu scripts/build-android.sh
   - pastikan AAR berisi jni/<abi>/libnuvio_engine.so untuk 4 ABI
   - perbaiki diagnostik Kotlin/AGP di android/app/src/main/java/app/sora/MainActivity.kt
   - verifikasi NuvioEngine.version memang ada di vendor/ sebelum memakainya
   - ukur keberhasilan: APK terpasang, URL trailer Sintel berputar, magnet publik
     menghasilkan metadata lalu playback

2. Windows
   - scripts/build-windows.ps1 -BuildEngine (butuh Docker Desktop, Linux container)
   - scripts/build-windows.ps1 -MpvDll <path mpv-2.dll> -Config Release
   - perbaiki diagnostik MSVC/llvm-mingw di windows/src/main.cpp
   - ukur keberhasilan: URL langsung berputar; magnet menghasilkan STREAM_PREPARED
     dengan URL loopback; keluar aplikasi tidak meninggalkan proses menggantung

3. iOS
   - scripts/build-apple.sh --build di macOS
   - pastikan ios/Vendor/nuvio-engine/platform/apple/NuvioEngine.xcframework ada
     dan canImport(NuvioEngine) bernilai true (bukan jalur placeholder)
   - perbaiki diagnostik Swift di ios/Sources/Sora/
   - putuskan MPVKit: dipakai (ganti PlayerView) atau dihapus dari project.yml
     sampai benar-benar dipakai — jangan biarkan dependency menganggur

Setelah Milestone 0 hijau, lanjut Milestone 1 (UI player, resume, buffer indicator),
Milestone 2 (subtitle), Milestone 3 (kebijakan upload/cache), Milestone 4
(distribusi + CI). Jangan melompat urutan.

# Aturan keras

Konten:
- Sora adalah pemutar, bukan katalog. Tidak ada addon, scraper, manifest Stremio,
  integrasi Torrentio/embedwave/IDLIX, atau daftar film berhak cipta.
- Input hanya magnet atau URL yang disediakan pengguna.
- Jangan pernah menambahkan sumber konten atas inisiatif sendiri, termasuk sebagai
  "contoh" atau "data demo".

Lisensi:
- App ini GPL-3.0 karena menautkan nuvio-engine. Jangan menambah dependensi dengan
  lisensi yang melarang relink atau disclosure source.
- Jangan menghapus atau menulis ulang LICENSE, THIRD_PARTY.md, NOTICE upstream.
- Sebelum menyentuh distribusi Android, baca celah lisensi nuvio-libass di
  THIRD_PARTY.md. Jangan menyarankan rilis publik tanpa menyelesaikannya.

Repo:
- Jangan commit vendor/, build/, *.aar, *.apk, *.xcframework, *.dll, atau secrets.
- Jangan hardcode path absolut, token, atau signing key.
- Jangan force push, jangan menulis ulang history, jangan mengubah remote.
- Jangan mengubah versi AGP/Kotlin/Gradle/NDK/CMake/Media3/MPVKit tanpa membaca
  file upstream yang menetapkannya lebih dulu, dan jelaskan alasannya.

Kualitas:
- Perubahan kecil dan terfokus. Satu milestone per rangkaian commit.
- Ikuti pola yang sudah ada di repo (struktur file, penamaan, gaya komentar).
- Komentar kode dalam bahasa Inggris; string UI dalam bahasa Indonesia.
- Jangan menambah abstraksi baru kalau satu file cukup.
- Jangan menulis ulang seluruh file untuk perubahan kecil.
- Setiap TODO yang kamu tinggalkan harus menyebut file dan alasan, bukan "TODO".

Kejujuran teknis:
- Jangan pernah menulis "sudah diuji", "build berhasil", atau "berfungsi" tanpa
  output perintah yang mendukungnya di sesi itu.
- Kalau ragu antara dua API upstream, buka vendor/ dan kutip signature aslinya.
- Kalau gagal, tulis error aslinya (bukan ringkasan), lalu hipotesis penyebabnya.

# Gaya per platform

Android (Kotlin, view-based):
- Namespace/appId: app.sora. minSdk 24, compileSdk 36, Media3 1.8.0.
- nuvio-engine AAR masuk lewat android/app/libs/, bukan Maven.
- Loopback cleartext hanya untuk 127.0.0.1/localhost (sudah ada
  network_security_config.xml). Jangan mengaktifkan cleartext global.
- Kalau menambah libass: jangan lupa libc++_shared.so per ABI.
- Pindahkan pekerjaan engine ke coroutine/IO; jangan blokir main thread.

iOS (SwiftUI):
- project.yml adalah sumber konfigurasi; jangan commit Sora.xcodeproj.
- Deployment target 16.1. Engine sebagai local Swift package di ios/Vendor/.
- Jaga jalur #if canImport(NuvioEngine) tetap valid supaya project masih compile
  sebelum xcframework dibangun.
- Kalau mengganti AVPlayer ke MPVKit, batasi perubahan di PlayerView.swift dan
  pertahankan permukaan PlayerModel.

Windows (C++20, Win32):
- libmpv hanya lewat LoadLibrary di windows/src/mpv_dynamic.h; jangan menambah
  import library mpv.
- nuvio-engine lewat import library saat -DNUVIO_ENGINE_DIR diisi; tanpa itu build
  harus tetap jalan tanpa dukungan magnet (SORA_HAS_NUVIO_ENGINE).
- Polling event engine tidak boleh memblokir UI thread: pindahkan ke worker dan
  kirim hasil via PostMessage.
- Selalu bersihkan: mpv_terminate_destroy, nuvio_engine_destroy, FreeLibrary.

# Format laporan setiap iterasi

1. Perubahan: file apa, kenapa, dan keputusan teknis yang diambil.
2. Verifikasi: perintah yang dijalankan + hasil ringkas (baris penting saja).
3. Sisa masalah: error asli, hipotesis, dan apa yang sudah dicoba.
4. Berikutnya: langkah konkret berikutnya, atau pertanyaan kalau butuh keputusan.

# Definisi selesai Milestone 0

- Android: APK terpasang; URL langsung berputar; magnet publik berputar; seek jalan.
- Windows: Sora.exe jalan; URL langsung berputar; magnet berputar lewat engine.
- iOS: build simulator sukses; URL langsung berputar; canImport(NuvioEngine) true.
- docs/BUILD.md diperbarui dengan versi yang benar-benar dipakai dan setiap
  penyimpangan dari catatan awal.
- Tidak ada artefak build, vendor/, atau secret yang masuk git.
```
