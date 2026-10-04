#!/bin/sh
# Download the Godot editor binary and Linux export templates used to build
# the Debian package. Idempotent.
set -eu
VER="${GODOT_VERSION:-4.5}"
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
if [ ! -f "$TPL/linux_release.x86_64" ]; then
    curl -fsSL -o "$DIR/templates.tpz" "$BASE/Godot_v${VER}-stable_export_templates.tpz"
    unzip -oqj "$DIR/templates.tpz" 'templates/linux_release.x86_64' 'templates/version.txt' -d "$TPL"
    rm "$DIR/templates.tpz"
fi
echo "Godot ${VER} ready: $DIR/godot"
