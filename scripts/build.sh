#!/usr/bin/env bash
# Build the single-file Windows benchmark: fetch demo -> overlay -> import -> generate preset -> export -> hash.
# Usage: GODOT=<path to Godot 4.7.2 binary> scripts/build.sh [workdir]     (default workdir: ./tps-bench)
# Needs the matching export templates installed (Godot's own template dir).
# Output: <repo>/build/OCGP-TPS.exe and build/OCGP-TPS.exe.sha256
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:?set GODOT to the Godot 4.7.2 executable}"
WORK="${1:-$HERE/tps-bench}"
OUT="$HERE/build"

rm -rf "$WORK"
"$HERE/scripts/setup.sh" "$WORK"

"$GODOT" --headless --path "$WORK" --import
# --no-lightmap: lean build (drops ~98 MB of lightmap GI data; the benchmark then refuses --gi lightmap)
"$GODOT" --headless --path "$WORK" --script res://ocgp_bench/export_list.gd -- --no-lightmap
mkdir -p "$WORK/build"
"$GODOT" --headless --path "$WORK" --export-release "Windows Desktop" build/OCGP-TPS.exe

mkdir -p "$OUT"
cp "$WORK/build/OCGP-TPS.exe" "$OUT/"
(cd "$OUT" && sha256sum OCGP-TPS.exe > OCGP-TPS.exe.sha256 && cat OCGP-TPS.exe.sha256)
