"""
tps_wrapper.py — OCGP launcher for the Godot "TPS" benchmark.

Two ways to run (the packaged exe is preferred and is what competitors get):

  1. PACKAGED   a single exported executable (OCGP-TPS.exe / ocgp_tps.x86_64) that contains the engine, the
                level and the baked route. Only that one file is fingerprinted.
                    --exe PATH, else the first OCGP-TPS* / ocgp_tps* file under ~/.ocgp/external/
  2. DEVELOPMENT  a Godot 4.7 binary plus the prepared project folder (see setup.sh).
                    --godot-path PATH --project-path DIR   (defaults: Godot* under ~/.ocgp/external/, and
                    ~/.ocgp/external/tps-bench)

Required engine flags are added here so competitors cannot forget them:
    --fixed-fps 60     fixed timestep: frame k is identical on every machine, but frames still render as fast
                       as the hardware allows (the benchmark aborts if this is missing)
    --disable-vsync    no display-rate cap
    --flush-stdout     events arrive live, not at exit
    --rendering-driver vulkan   pinned so results compare across machines (D3D12 is the Windows default)

The JSON event lines (start / sector / complete) are relayed on stdout, same protocol as 3dpoc.py.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

EXTERNAL = Path.home() / ".ocgp" / "external"
BENCH_SCENE = "res://ocgp_bench/bench.tscn"
MANIFEST = Path(__file__).resolve().parent / "manifest.json"
ENGINE_FLAGS = ["--rendering-driver", "vulkan", "--disable-vsync", "--fixed-fps", "60", "--flush-stdout"]


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def fail(code: str, message: str, **extra) -> int:
    emit({"event": "complete", "error": code, "message": message, **extra})
    return 1


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def find_packaged(explicit: str | None) -> Path | None:
    if explicit:
        p = Path(explicit)
        return p if p.is_file() else None
    if EXTERNAL.is_dir():
        for p in sorted(EXTERNAL.rglob("*")):
            n = p.name.lower()
            if p.is_file() and (n.startswith("ocgp-tps") or n.startswith("ocgp_tps")):
                return p
    return None


def find_godot(explicit: str | None) -> Path | None:
    if explicit:
        p = Path(explicit)
        return p if p.is_file() else None
    if EXTERNAL.is_dir():
        for p in sorted(EXTERNAL.rglob("*")):
            n = p.name.lower()
            if p.is_file() and (n.startswith("godot_v") or (n.startswith("godot") and "console" in n)):
                return p
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description="OCGP TPS (Godot) wrapper")
    ap.add_argument("--frames", type=int, default=3000)
    ap.add_argument("--sectors", type=int, default=10)
    ap.add_argument("--warmup", type=int, default=300)
    ap.add_argument("--res", choices=["720p", "1080p", "4k"], default="1080p",
                    help="Internal render resolution (720p=Small, 1080p=Medium, 4k=Large).")
    ap.add_argument("--gi", choices=["voxel", "sdfgi", "lightmap"], default="voxel")
    ap.add_argument("--gi-quality", choices=["low", "high"], default="high")
    ap.add_argument("--only-sector", type=int, default=None, help="Debug; result not submittable.")
    ap.add_argument("--exe", default=None, help="Packaged single-file build (preferred).")
    ap.add_argument("--godot-path", default=None)
    ap.add_argument("--project-path", default=None)
    args = ap.parse_args()

    bench_args = ["--frames", str(args.frames), "--sectors", str(args.sectors), "--warmup", str(args.warmup),
                  "--gi", args.gi, "--gi-quality", args.gi_quality, "--res", args.res]
    if args.only_sector is not None:
        bench_args += ["--only-sector", str(args.only_sector)]

    packaged = find_packaged(args.exe)
    if packaged is not None:
        # The whole benchmark (engine + level + route + robots) is this one file: one hash covers it.
        fingerprints = {"exe": sha256(packaged)}
        cmd = [str(packaged), *ENGINE_FLAGS, "--", *bench_args]
    else:
        godot = find_godot(args.godot_path)
        project = Path(args.project_path) if args.project_path else EXTERNAL / "tps-bench"
        if godot is None:
            return fail("godot_not_found",
                        "No packaged OCGP-TPS build and no Godot 4.7 binary found "
                        "(use --exe, or --godot-path/--project-path, or put them under ~/.ocgp/external/).")
        if not (project / "ocgp_bench" / "bench.gd").is_file():
            return fail("project_not_found", f"Prepared TPS project not found at {project} (run setup.sh).")
        fingerprints = {"godot": sha256(godot)}
        for rel in ("ocgp_bench/bench.gd", "ocgp_bench/level_static.gd", "ocgp_bench/robot_stub.gd",
                    "ocgp_bench/frame_stats.gd", "ocgp_bench/bench.tscn", "project.godot",
                    "ocgp_bench/route.ocgp", "ocgp_bench/activity.ocgp",
                    "ocgp_bench/path.json", "ocgp_bench/activity.json"):   # data files: new names, then legacy
            if (project / rel).is_file():
                fingerprints[rel] = sha256(project / rel)
        cmd = [str(godot), "--path", str(project), *ENGINE_FLAGS, BENCH_SCENE, "--", *bench_args]

    # Enforce the allowlist once known_hashes is populated (empty = unverified prototype).
    try:
        known = json.loads(MANIFEST.read_text("utf-8")).get("external_dependency", {}).get("known_hashes", {})
    except Exception:
        known = {}
    if known:
        bad = [k for k, v in fingerprints.items() if v not in known]
        if bad:
            return fail("unrecognized_files", f"Not on the allowlist: {bad}", fingerprints=fingerprints)
    else:
        print("WARNING: known_hashes is empty - run is unverified (prototype).", file=sys.stderr)

    completed = False
    with subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True) as proc:
        assert proc.stdout is not None
        for line in proc.stdout:
            line = line.strip()
            if not line.startswith("{"):
                continue  # engine banner / warnings
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if ev.get("event") == "start":
                ev["fingerprints"] = fingerprints
            completed = completed or ev.get("event") == "complete"
            emit(ev)
        rc = proc.wait()

    if not completed:
        return fail("execution_failed", f"Benchmark exited (code {rc}) without a complete event.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
