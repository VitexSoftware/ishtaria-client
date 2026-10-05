#!/bin/sh
# Download the Godot editor binary and the export templates used to build
# the Debian package (default) and, on request, the Linux arm64, Windows and macOS clients.
#   PLATFORMS="linux linux-arm64 windows macos" tools/fetch-godot.sh
# Idempotent.
set -eu
VER="${GODOT_VERSION:-4.5}"
PLATFORMS="${PLATFORMS:-linux}"
BASE="https://github.com/godotengine/godot/releases/download/${VER}-stable"
DIR="$(cd "$(dirname "$0")" && pwd)/godot"
TPL="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${VER}.stable"
mkdir -p "$DIR" "$TPL"
if [ ! -x "$DIR/godot" ]; then
    curl -fsSL -o "$DIR/godot.zip" "$BASE/Godot_v${VER}-stable_linux.x86_64.zip"
    unzip -oq "$DIR/godot.zip" -d "$DIR"
    mv "$DIR/Godot_v${VER}-stable_linux.x86_64" "$DIR/godot"
    rm "$DIR/godot.zip"
fi
files="templates/version.txt"
for platform in $PLATFORMS; do
    case "$platform" in
        linux) files="$files templates/linux_release.x86_64" ;;
        linux-arm64) files="$files templates/linux_release.arm64" ;;
        windows) files="$files templates/windows_release_x86_64.exe templates/windows_release_x86_64_console.exe" ;;
        macos) files="$files templates/macos.zip" ;;
        *) echo "unknown platform: $platform" >&2; exit 1 ;;
    esac
done
missing=0
for f in $files; do [ -f "$TPL/$(basename "$f")" ] || missing=1; done
if [ "$missing" = 1 ]; then
    curl -fsSL -o "$DIR/templates.tpz" "$BASE/Godot_v${VER}-stable_export_templates.tpz"
    # shellcheck disable=SC2086
    unzip -oqj "$DIR/templates.tpz" $files -d "$TPL"
    rm "$DIR/templates.tpz"
fi
echo "Godot ${VER} ready: $DIR/godot"
