#!/usr/bin/env bash
# Builds the Apple side. macOS only.
#
#   scripts/build-apple.sh              engine xcframework + Xcode project
#   scripts/build-apple.sh --build      ... and run xcodebuild for the simulator
#   scripts/build-apple.sh --open       ... and open the generated project
#
# What it does:
#   1. vendor/, if empty -> scripts/fetch-deps.sh
#   2. builds nuvio-engine's NuvioEngine.xcframework (OpenSSL + libtorrent,
#      slow on the first run)
#   3. copies nuvio-engine/platform/apple into ios/Vendor/nuvio-engine/... so the
#      local Swift package in ios/project.yml resolves
#   4. runs xcodegen (MPVKit is fetched by SPM at project generation time)

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
vendor="$repo_root/vendor"
ios_root="$repo_root/ios"
vendor_package="$ios_root/Vendor/nuvio-engine/platform/apple"

mode=generate
for argument in "$@"; do
    case "$argument" in
        --build) mode=build ;;
        --open) mode=open ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "unknown argument: $argument" >&2; exit 2 ;;
    esac
done

if [[ "$(uname -s)" != Darwin ]]; then
    cat >&2 <<'EOF'
error: the Apple target needs macOS.

Nothing in ios/ can be built elsewhere: NuvioEngine.xcframework requires the
Apple SDKs, and MPVKit ships prebuilt frameworks for Apple platforms only.
EOF
    exit 2
fi

for tool in cmake ninja xcodebuild git; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: missing $tool (brew install cmake ninja)" >&2
        exit 2
    }
done

if [[ ! -d "$vendor/nuvio-engine" ]]; then
    "$repo_root/scripts/fetch-deps.sh"
fi

# ------------------------------------------------- engine xcframework

if [[ -d "$vendor/nuvio-engine/platform/apple/NuvioEngine.xcframework" ]]; then
    echo "==> reusing existing NuvioEngine.xcframework"
else
    echo "==> building NuvioEngine.xcframework (first run compiles OpenSSL and"
    echo "    libtorrent for two Apple slices; expect a long wait)"
    "$vendor/nuvio-engine/scripts/build-apple-xcframework.sh"
fi

echo "==> staging the engine Swift package into ios/Vendor"
mkdir -p "$vendor_package"
rsync -a --delete \
    --exclude 'build/' \
    --exclude '.deps/' \
    "$vendor/nuvio-engine/platform/apple/" "$vendor_package/"

if [[ ! -d "$vendor_package/NuvioEngine.xcframework" ]]; then
    echo "error: NuvioEngine.xcframework was not copied into ios/Vendor" >&2
    exit 1
fi

# ------------------------------------------------- Xcode project

if ! command -v xcodegen >/dev/null 2>&1; then
    cat <<'EOF'
error: xcodegen is not installed.

    brew install xcodegen
    scripts/build-apple.sh

Alternatively create a project by hand: File > New > Project, add
ios/Sources/Sora, then add the local package at
ios/Vendor/nuvio-engine/platform/apple and the MPVKit SPM dependency.
EOF
    exit 2
fi

echo "==> generating ios/Sora.xcodeproj"
(cd "$ios_root" && xcodegen generate)

case "$mode" in
    build)
        echo "==> xcodebuild (iOS Simulator)"
        (
            cd "$ios_root"
            xcodebuild \
                -project Sora.xcodeproj \
                -scheme Sora \
                -configuration Debug \
                -sdk iphonesimulator \
                -destination 'generic/platform=iOS Simulator' \
                CODE_SIGNING_ALLOWED=NO \
                build
        )
        ;;
    open)
        open "$ios_root/Sora.xcodeproj"
        ;;
esac

cat <<'EOF'

==> done
    project: ios/Sora.xcodeproj

TODO(cursor): Sora currently plays direct URLs through AVPlayer. Replace
PlayerView with MPVKit and route the engine's loopback URL into mpv; the
NuvioEngine package and the EngineClient bridge are already in place.
EOF
