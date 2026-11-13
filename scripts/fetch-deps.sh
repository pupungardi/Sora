#!/usr/bin/env bash
# Clones the upstream Nuvio sources into vendor/ at a known ref.
#
#   scripts/fetch-deps.sh                 engine + libass + MPVKit
#   scripts/fetch-deps.sh --with-self-host  also the optional sync backend
#
# Pin a different revision with NUVIO_ENGINE_REF / NUVIO_LIBASS_REF /
# NUVIO_MPVKIT_REF / NUVIO_SELF_HOST_REF. Nothing here is vendored into git:
# vendor/ is ignored, so re-running this script is always safe.

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
vendor="$repo_root/vendor"
mkdir -p "$vendor"

engine_ref=${NUVIO_ENGINE_REF:-main}
libass_ref=${NUVIO_LIBASS_REF:-main}
mpvkit_ref=${NUVIO_MPVKIT_REF:-0.41.0-n8.1.2-nuvio.5}
self_host_ref=${NUVIO_SELF_HOST_REF:-main}

with_self_host=0
for argument in "$@"; do
    case "$argument" in
        --with-self-host) with_self_host=1 ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        *)
            echo "unknown argument: $argument" >&2
            exit 2
            ;;
    esac
done

clone_or_update() {
    local name=$1
    local url=$2
    local ref=$3
    local destination="$vendor/$name"

    if [[ -d "$destination/.git" ]]; then
        echo "==> $name: fetching $ref"
        git -C "$destination" fetch --depth 1 origin "$ref"
        git -C "$destination" checkout --quiet FETCH_HEAD
    else
        echo "==> $name: cloning $ref"
        git clone --depth 1 --branch "$ref" "$url" "$destination"
    fi

    printf '    %s @ %s\n' "$name" "$(git -C "$destination" rev-parse HEAD)"
}

clone_or_update nuvio-engine https://github.com/NuvioMedia/nuvio-engine.git "$engine_ref"
clone_or_update nuvio-libass https://github.com/NuvioMedia/nuvio-libass.git "$libass_ref"
clone_or_update MPVKit https://github.com/NuvioMedia/MPVKit.git "$mpvkit_ref"

if [[ "$with_self_host" == 1 ]]; then
    clone_or_update self-host https://github.com/NuvioMedia/self-host.git "$self_host_ref"
fi

cat <<'EOF'

Done. Next steps:

  Android   scripts/build-android.sh          (must run on Linux or macOS)
  Apple     scripts/build-apple.sh            (must run on macOS)
  Windows   scripts/build-windows.ps1         (run in PowerShell)
  Backend   cd vendor/self-host && ./nuvio setup --domain <host>

Licences are summarised in THIRD_PARTY.md. nuvio-engine is GPL-3.0-or-later,
so any distributed build of Sora must ship its complete source under the same
licence.
EOF
