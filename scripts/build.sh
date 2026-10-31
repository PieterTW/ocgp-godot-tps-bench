#!/usr/bin/env bash
# Build the single-file Windows benchmark: fetch demo -> overlay -> import -> generate preset -> export -> hash.
# Usage: GODOT=<path to Godot 4.7.2 binary> [VERSION=v0.1.2] scripts/build.sh [workdir]     (default workdir: ./tps-bench)
# Needs the matching export templates installed (Godot's own template dir).
# Output: <repo>/build/OCGP-TPS[-<VERSION>].exe and its .sha256
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:?set GODOT to the Godot 4.7.2 executable}"
WORK="${1:-$HERE/tps-bench}"
OUT="$HERE/build"
# Unversioned by default (local/manual builds); CI passes VERSION=$GITHUB_REF_NAME on a tag push.
EXE_NAME="OCGP-TPS${VERSION:+-$VERSION}.exe"

rm -rf "$WORK"
echo "==> setup: fetching demo + overlay"
"$HERE/scripts/setup.sh" "$WORK"

echo "==> importing assets (slow, several minutes on CI)"
"$GODOT" --headless --path "$WORK" --import
echo "==> import done"

# --no-lightmap: lean build (drops ~98 MB of lightmap GI data; the benchmark then refuses --gi lightmap)
echo "==> regenerating export_presets.cfg"
"$GODOT" --headless --path "$WORK" --script res://ocgp_bench/export_list.gd -- --no-lightmap
mkdir -p "$WORK/build"
echo "==> exporting Windows build (slow, several minutes on CI)"
"$GODOT" --headless --path "$WORK" --export-release "Windows Desktop" build/OCGP-TPS.exe
echo "==> export done"

mkdir -p "$OUT"
# the music is not part of the benchmark; fail loudly if it ever sneaks back into the pack
if grep -qa "level_music" "$WORK/build/OCGP-TPS.exe"; then echo "ERROR: level_music.ogg is inside the exe" >&2; exit 1; fi
cp "$WORK/build/OCGP-TPS.exe" "$OUT/$EXE_NAME"
(cd "$OUT" && sha256sum "$EXE_NAME" > "$EXE_NAME.sha256" && cat "$EXE_NAME.sha256")
