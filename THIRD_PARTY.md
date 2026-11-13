# Third-party components

Sora itself is GPL-3.0 (see `LICENSE`) because it links `nuvio-engine`.

| Component | Role | Licence | Notes |
|---|---|---|---|
| [nuvio-engine](https://github.com/NuvioMedia/nuvio-engine) | torrent + streaming core | **GPL-3.0-or-later** | Dominates Sora's licence. Binary distribution requires complete corresponding source. |
| [nuvio-libass](https://github.com/NuvioMedia/nuvio-libass) | ASS/SSA rendering for Android | **no LICENSE file** | See "libass gap" below. |
| [MPVKit](https://github.com/NuvioMedia/MPVKit) | libmpv for Apple platforms | **LGPL-3.0** | Prebuilt frameworks; keep it dynamically linked and ship its licence text. |
| [mpv](https://mpv.io) / `mpv-2.dll` | Windows video output | GPL-2.0-or-later or LGPL-2.1-or-later depending on the build | The official Windows build is GPL. Redistributing it keeps Sora GPL-compatible either way. |
| [AndroidX Media3](https://github.com/androidx/media) | ExoPlayer (Android) | Apache-2.0 | |
| [self-host](https://github.com/NuvioMedia/self-host) | optional sync/account backend | Apache-2.0 | Not linked into the app; runs as a server. |

Transitive dependencies pulled in by `nuvio-engine` (libtorrent, Boost, OpenSSL,
try_signal) are listed in that repository's `THIRD_PARTY_NOTICES.md`; the engine
build vendors them with pinned checksums.

## libass gap — resolve before shipping Android

`nuvio-libass` carries `ATTRIBUTION.md` but **no `LICENSE` file**. It derives
from [peerless2012/libass-android](https://github.com/peerless2012/libass-android)
(MIT) via a fork, and MIT requires the copyright notice and permission text to
travel with the code. Because that text is absent, the conservative reading is
"all rights reserved, no distribution permission."

Before publishing an Android build that bundles it, pick one:

1. Ask Nuvio to add the upstream MIT notice to `nuvio-libass`, or
2. use `peerless2012/libass-android` directly (MIT, notice included), or
3. drop libass and rely on ExoPlayer's built-in SubRip/TTML support, losing
   ASS/SSA styling.

Until then, `scripts/build-android.sh` builds libass only when you pass
`--with-libass`, and that path is a local build, not a distribution.

## GPL obligations in practice

If you distribute a Sora binary:

- publish the exact source used, including your local changes;
- keep the GPL-3.0 text and copyright notices intact;
- do not add restrictions (DRM, anti-tamper, App Store terms that forbid
  relinking) that conflict with GPL-3.0. This is the usual reason GPL apps are
  distributed outside the iOS App Store.

This file is a summary, not legal advice.
