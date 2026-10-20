#!/usr/bin/env bash
# Fetch the Godot TPS demo at the pinned commit and overlay the OCGP benchmark.
# Usage: scripts/setup.sh [destination-dir]      (default: ./tps-bench)
set -euo pipefail

PIN=a82f15448e9b015440d3bbdf5e10801b260c4e9f   # godotengine/tps-demo @ 2026-08-31 (targets Godot 4.7)
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-tps-bench}"

mkdir -p "$DEST"
git -C "$DEST" init -q
git -C "$DEST" fetch -q --depth 1 https://github.com/godotengine/tps-demo "$PIN"
git -C "$DEST" checkout -q FETCH_HEAD
cp -r "$HERE/ocgp_bench" "$DEST/"

# project.godot changes: main-scene override for exported builds (feature tag "ocgp", set by the export preset)
# and HDR off in those builds. Normal editor runs ignore the .ocgp overrides.
git -C "$DEST" apply --ignore-whitespace "$HERE/patches/project.godot.patch"

echo "Done. Import once (slow, ~minutes):  godot --headless --path $DEST --import"
echo "Then run:  godot --path $DEST --disable-vsync --fixed-fps 60 --flush-stdout res://ocgp_bench/bench.tscn -- --frames 3000"
