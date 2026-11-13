#!/usr/bin/env bash
# Builds the Android pieces and, optionally, the debug APK.
#
#   scripts/build-android.sh                engine AAR + APK
#   scripts/build-android.sh --engine-only  engine AAR only
#   scripts/build-android.sh --with-libass  also build nuvio-libass and stage
#                                           libc++_shared.so for every ABI
#
# nuvio-engine refuses to build its Android dependencies on a non-Darwin/Linux
# host (scripts/build-android-openssl.sh exits with "unsupported Android build
# host"), so this script must run inside WSL2/Ubuntu, a Linux container, or on
# macOS. On native Windows it stops with an explanation instead of a cryptic
# Gradle failure.

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
vendor="$repo_root/vendor"
android_app="$repo_root/android"
libs="$android_app/app/libs"

engine_only=0
with_libass=0
for argument in "$@"; do
    case "$argument" in
        --engine-only) engine_only=1 ;;
        --with-libass) with_libass=1 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown argument: $argument" >&2; exit 2 ;;
    esac
done

case "$(uname -s)" in
    Darwin|Linux) ;;
    *)
        cat >&2 <<'EOF'
error: unsupported Android build host.

nuvio-engine's OpenSSL step only supports Darwin and Linux hosts, and Git Bash
still reports MINGW64_NT, so it fails there too.

Run this script inside WSL2:

    wsl --install -d Ubuntu
    # then, inside Ubuntu, install JDK 17 and the Android SDK/NDK and rerun.

See docs/BUILD.md for the exact SDK/NDK/CMake versions.
EOF
        exit 2
        ;;
esac

if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
    echo "error: set ANDROID_HOME (or ANDROID_SDK_ROOT) first." >&2
    exit 2
fi
android_sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
: "${JAVA_HOME:?set JAVA_HOME to a JDK 17 install}"

ndk_version=29.0.14206865
ndk_root="$android_sdk/ndk/$ndk_version"
if [[ ! -d "$ndk_root" ]]; then
    echo "error: NDK $ndk_version not found at $ndk_root" >&2
    echo "       install it with: sdkmanager \"ndk;$ndk_version\" \"cmake;4.1.2\"" >&2
    exit 2
fi

if [[ ! -d "$vendor/nuvio-engine" ]]; then
    echo "==> vendor/nuvio-engine missing, running scripts/fetch-deps.sh"
    "$repo_root/scripts/fetch-deps.sh"
fi

mkdir -p "$libs"

# ---------------------------------------------------------------- nuvio-engine

echo "==> building nuvio-engine AAR (first run downloads and compiles OpenSSL"
echo "    3.5.7 + libtorrent for four ABIs; expect a long wait and several GB)"
(
    cd "$vendor/nuvio-engine/platform/android"
    ./gradlew :engine:assembleRelease --no-daemon
)

engine_aar="$vendor/nuvio-engine/platform/android/engine/build/outputs/aar/engine-release.aar"
if [[ ! -f "$engine_aar" ]]; then
    echo "error: expected $engine_aar" >&2
    exit 1
fi
cp -f "$engine_aar" "$libs/engine-release.aar"
echo "    staged app/libs/engine-release.aar"

# ---------------------------------------------------------------- nuvio-libass

if [[ "$with_libass" == 1 ]]; then
    if [[ ! -d "$vendor/nuvio-libass" ]]; then
        echo "error: vendor/nuvio-libass missing; run scripts/fetch-deps.sh" >&2
        exit 2
    fi

    echo "==> building nuvio-libass AAR"
    (
        cd "$vendor/nuvio-libass"
        ./gradlew assembleRelease --no-daemon
    )

    libass_aar=$(find "$vendor/nuvio-libass" -name 'nuvio-libass-release.aar' -print -quit)
    if [[ -z "$libass_aar" ]]; then
        libass_aar=$(find "$vendor/nuvio-libass/build/outputs/aar" -name '*-release.aar' -print -quit)
    fi
    if [[ -z "$libass_aar" ]]; then
        echo "error: could not find the nuvio-libass AAR" >&2
        exit 1
    fi
    cp -f "$libass_aar" "$libs/nuvio-libass-release.aar"
    echo "    staged app/libs/nuvio-libass-release.aar"

    # nuvio-libass deliberately excludes libc++_shared.so from its AAR; the app
    # has to supply it. Copy the NDK's copy for each ABI.
    host_tag=linux-x86_64
    [[ "$(uname -s)" == Darwin ]] && host_tag=darwin-x86_64
    declare -A abi_triple=(
        [arm64-v8a]=aarch64-linux-android
        [armeabi-v7a]=arm-linux-androideabi
        [x86]=i686-linux-android
        [x86_64]=x86_64-linux-android
    )
    for abi in "${!abi_triple[@]}"; do
        source_so="$ndk_root/toolchains/llvm/prebuilt/$host_tag/sysroot/usr/lib/${abi_triple[$abi]}/libc++_shared.so"
        if [[ -f "$source_so" ]]; then
            mkdir -p "$android_app/app/src/main/jniLibs/$abi"
            cp -f "$source_so" "$android_app/app/src/main/jniLibs/$abi/libc++_shared.so"
        else
            echo "warning: missing $source_so" >&2
        fi
    done
    echo "    staged app/src/main/jniLibs/<abi>/libc++_shared.so"
fi

if [[ "$engine_only" == 1 ]]; then
    echo "==> done (engine only)"
    exit 0
fi

# ---------------------------------------------------------------- debug APK

echo "==> building debug APK"
(
    cd "$android_app"
    ./gradlew :app:assembleDebug --no-daemon
)

cat <<EOF

==> done
    APK: android/app/build/outputs/apk/debug/app-debug.apk
    install: adb install -r android/app/build/outputs/apk/debug/app-debug.apk
EOF
