# OCGP "TPS" benchmark (prototype)

A fixed-frame, uncapped-frame-rate benchmark built on the Godot **Third Person Shooter demo level**
([godotengine/tps-demo](https://github.com/godotengine/tps-demo)). A faster GPU renders the same N frames in
less wall-clock time; the score is the **sum of sector times in ms, lower is better** — same protocol as `3dpoc.py`.
Windows only for now.

This repo contains only the OCGP overlay (scripts, scene, recorded route, wrapper, manifest) and the build
pipeline. The demo's assets are **not** stored here — `scripts/setup.sh` fetches the demo at a pinned commit.

| Path | What it is |
|---|---|
| `ocgp_bench/` | the benchmark: scene + scripts, `route.ocgp` (recorded camera/player route), `activity.ocgp` (baked robots), record / bake / export tools |
| `patches/` | the two small changes made to the demo itself (`project.godot`, `level.tscn`) |
| `scripts/` | `setup.sh` (fetch + overlay), `build.sh` (setup, import, export, hash), `stamp_manifest.py`, `package_testers.py` |
| `tps_wrapper.py`, `manifest.json` | the OCGP workload wrapper and manifest |
| `tester/` | launcher + instructions for the tester package |
| `.github/workflows/build.yml` | builds the exe on a `v*` tag and publishes a release |
| `OUTPUT.md` | what a run reports (events, fields, error codes) — for deciding what OCGP captures |
| `NOTICE.md` | third-party licences / attribution |

## Getting the benchmark

**Release build (normal use):** a tag push (`v*`) builds `OCGP-TPS.exe` in GitHub Actions and attaches to the release:
`OCGP-TPS.exe`, `OCGP-TPS.exe.sha256`, a `manifest.json` stamped with the exe's hash in `known_hashes`,
`OCGP-TPS-tester.zip` and `NOTICE.md`. The committed `manifest.json` keeps `known_hashes` empty on purpose; the
exe is not byte-reproducible, so the hash of the released file is the one that counts.

**Build it yourself** (needs Godot 4.7.2 and its export templates installed):

```bash
GODOT=/path/to/Godot_v4.7.2-stable_win64_console.exe scripts/build.sh    # -> build/OCGP-TPS.exe + .sha256
python scripts/package_testers.py build/OCGP-TPS.exe build/OCGP-TPS-tester.zip   # optional tester package
```

`build.sh` runs `setup.sh` into `./tps-bench` (a fresh checkout of the demo at the pinned commit with the overlay
and patches applied), imports the assets (slow, minutes), generates `export_presets.cfg` with
`ocgp_bench/export_list.gd --no-lightmap` and exports the Windows preset.

**Development setup** (to run from the editor / record / bake):

```bash
scripts/setup.sh tps-bench                              # fetch tps-demo @ pinned commit + overlay + patches
godot --headless --path tps-bench --import              # one-time asset import (slow; see Known issues)
```

Needs **Godot 4.7.x** (the demo's `project.godot` targets 4.7). Tested with 4.7.2-stable.

## Run

Direct (what the wrapper does for you), from the development setup:

```bash
godot --path tps-bench --rendering-driver vulkan --disable-vsync --fixed-fps 60 --flush-stdout \
      res://ocgp_bench/bench.tscn -- --variant Medium --output result.txt
```

Via the wrapper: `python tps_wrapper.py --godot-path <godot> --project-path tps-bench --variant Medium`, or with the
packaged exe `python tps_wrapper.py --exe OCGP-TPS.exe --variant Medium`.

| Option (after `--`) | Meaning |
|---|---|
| `--variant Small\|Medium\|Large` | named preset: sets resolution, frames and sectors (table below). Cannot be combined with `--frames` / `--sectors` / `--res` (`invalid_args`). Also accepted before the `--` separator |
| `--output FILE` | also write every event (one JSON line each) to FILE; relative paths resolve against the exe's folder. Needed for the packaged exe, which has no console |
| `--frames N` | measured frames (must divide by `--sectors`) — default 2000 |
| `--sectors S` | timed sectors, default 10 |
| `--warmup W` | untimed frames, touring every vantage first — default 300 |
| `--res 720p\|1080p\|4k` | internal render resolution (default 1080p); the variants below use it as the difficulty axis |
| `--gi voxel\|sdfgi\|lightmap`, `--gi-quality low\|high` | GI profile (default voxel/high) |
| `--no-activity`, `--no-player`, `--no-path` | diagnostics: drop the robots / the character / the recorded route |
| `--profile` | diagnostic (marks the run non-submittable): adds a `profile` object to every sector event - per-frame `frame_ms`, `gpu_ms` (GPU time of the render), `render_cpu_ms` (CPU time submitting it), `process_ms` (scripts / animation / particles) and `draw_calls`. If `gpu_ms` is well below `frame_ms`, the run is CPU-limited. |
| `--robot-limit N` | diagnostic: spawn only the first N baked robots (untested) |
| `--no-hud` | hide the live overlay (see below) |
| *debug:* `--only-sector N`, `--probe`, `--debug-shots DIR`, `--debug-size WxH` | mark the run `debug_run:true` (not submittable) |

## Variants (difficulty = resolution)

| Variant | Resolution | Frames | Sectors |
|---|---|---|---|
| Small | 1280x720 | 10 000 | 10 x 1 000 |
| Medium | 1920x1080 | 10 000 | 10 x 1 000 |
| Large | 3840x2160 | 5 000 | 10 x 500 |

`--res` only accepts those three values (anything else aborts with `invalid_args`) and is **not** a debug option;
`--debug-size WxH` still exists for diagnostics and marks the run non-submittable. The 3D scene always renders at
the full internal resolution (viewport stretch mode), but the on-screen window is capped at 1920x1080, so a 4K run
fits a 1080p monitor and is simply displayed downscaled. The `start` event reports `resolution`, `render_size`
and `window_size`; the server should check `render_size` against the variant. Frame counts are guesses: Large is
set lower because 4K frames cost far more; tune them once 720p / 4K timings are known across GPUs.

## "Fixed frames, variable frame rate" — how that works here

* `--fixed-fps 60` does **not** cap the frame rate. It fixes the *timestep*: every frame advances the world by
  exactly 1/60 s, and frames are rendered as fast as the hardware can. (Measured headless on 4.4.1: 3 000 frames = 50 s of
  game time in ~2 s of wall time.)
* The benchmark **aborts** (`fixed_timestep_required`) if any frame's delta differs from 1/60 s, so a run
  launched without the flag cannot produce a score.
* Frame *k* is a pure function of *k*: camera pose is computed from the frame index; the forklift
  `AnimationPlayer` is stepped manually from it; forklift model choice and particle seeds are pinned; physics is off;
  the player's `settings.ini` is ignored (settings are pinned in code); TAA/MSAA/vendor upscalers are off.
  The `TIME`-driven core shader and CPU particles follow the fixed timestep.

* The 3D scene renders at a **fixed 1920x1080 internal resolution** (viewport stretch mode), independent of the
  OS window rect; the check validates that internal size and the start event records the actual `window_size`.
  (First Windows run showed the window client area as 1930x1090, which broke an earlier window-size check.)
* The rendering driver is pinned (`--rendering-driver vulkan`); Godot 4.7 defaults to D3D12 on Windows, which
  would make scores incomparable across machines. The start event records the driver used.

## What was changed in the demo level

* `level.gd` replaced at runtime by `ocgp_bench/level_static.gd` (GI setup kept; player/robot spawning,
  multiplayer and input removed).
* Removed at load: music, debug label, spawners/spawn points. Audio bus muted.
* Camera: a **recorded walkthrough** if `ocgp_bench/route.ocgp` exists (see below), otherwise 10 fixed vantage
  points (from the demo's spawn markers) with a 360° yaw sweep each (`VANTAGES` in `bench.gd`; `--no-path` forces this).

> **Data file names:** the route and robot files are `route.ocgp` and `activity.ocgp` (plain JSON inside). Godot
> treats `.json` as a resource and would not copy it verbatim into an exported build; an unknown extension is shipped
> as-is via the export include filter. Existing `path.json` / `activity.json` still load in the editor; rename them,
> or re-run record/bake, before building a packaged exe.

## Recording a walkthrough

The demo has no scripted tour, so you record one by playing:

```bash
godot --path tps-bench res://ocgp_bench/record.tscn      # normal game window, real player + robots
```
Press **F9** to start recording, walk the route (WASD + mouse; don't shoot — it adds camera shake), press **F9**
again to stop. It writes `ocgp_bench/route.ocgp` at 20 Hz: the camera (position / rotation / FOV) **and the player**
(feet position, model facing, animation state, motion, aim); ~60-120 s is plenty.

Playback: progress along the route is `frame_index / total_frames`, so every variant flies the *same* route; a
longer variant simply flies it more slowly (more frames per metre). Sectors are consecutive segments of the route.
Position uses Catmull-Rom interpolation (character and camera), rotation uses slerp. The warmup flies the whole route once, quickly.
The start event reports `camera_path`, `path_samples` and `path_sha256` so the server can verify the route, and
the wrapper adds the file to its fingerprints. **Commit the final `route.ocgp` with the benchmark; competitors must
not be able to change it.**

**Player character (third-person):** the recorded camera is the game's own third-person camera, and playback now
spawns the real player model (input, physics, camera rig, UI overlays and bullets stripped) and replays the
recorded feet position, facing and animation state, so you see the character walking through the level. The
walk-cycle is stepped at `recorded route speed / playback route speed`, so the feet stay matched to the ground at any
frame count (a long variant is simply slow motion, a short one fast-forward). Routes recorded with the earlier
version of `record.gd` (camera only, no player track) still play, without the character; re-record to get one.
`--no-player` disables it. Re-recording changes `route.ocgp`, so **bake the robots again**.

## Activity layer: scripted robots

Without it the level is a static fly-through. The activity layer adds red robots (the demo's enemies) beside the
route, so the benchmark also renders skinned characters, lasers, impact blasts, CPU particles and extra shadow-casting
lights.

1. **Bake once** after recording the route (robots keep clear of both the player's path and the camera's) (needs the level's collision, runs headless):
   ```bash
   godot --headless --path tps-bench res://ocgp_bench/bake.tscn -- --robots 12 --ahead 6
   ```
   Writes `ocgp_bench/activity.ocgp`: robot positions found with physics ray casts (open floor beside the route,
   headroom, clearance, spacing), each facing the oncoming camera, with its laser length measured against the
   walls. The file stores the route's sha256; if `route.ocgp` changes, the benchmark aborts with
   `activity_path_mismatch` until you bake again. Tunables: `--ahead` (metres ahead of the camera, default 6), `--offset-min` (min sideways distance, 3.5) and
   `--route-clearance` (min distance to ANY route point, 3.0) - robots are large, so the camera never clips one.
   If fewer robots are placed than requested, the route has little
   open floor at the sampled spots - re-record through more open areas or lower `--robots`.
2. **Playback:** robots are the real `red_robot.tscn` with its AI replaced by a stub (`robot_stub.gd`). Each robot
   loops every 600 frames: idle -> raise cannon (frames 150-180) -> **fire** (frame 240; laser, light, particles,
   impact blast at the measured hit point) -> lower cannon (330-360). Robots are staggered by a baked phase.
   Everything is a function of the frame index; particle seeds are fixed; the laser material is per-robot.
   `--no-activity` disables it.
3. Warmup fires one extra shot per robot so laser/blast resources are loaded before timing.

Note: `--only-sector` (debug) does not pre-age robot animation state, so an isolated sector is not identical to
the same sector in a full run.

## Live overlay

Top-left, updated every 15 frames (so the overlay's own cost is negligible):

```
TPS  1080p  vulkan  NVIDIA GeForce RTX 4090
frame 4321 / 10000   sector 5/10
2.80 ms  357 fps   worst 4.92 ms
avg 2.78 ms   elapsed 12.0 s
lows  1% 230   0.1% 180   0.01% 150   min 148 fps
```
`frame` is the measured-frame counter; the second ms line is the average over the last 15 frames (`worst` is the
longest single frame in that window - spikes show up here); `avg` and `elapsed` cover the whole timed run. During
warmup it shows `warming up n / N` (plus a glyph sample, so font setup happens before timing and does not show up as a first-frame hitch). Text size scales with the internal resolution. The overlay is part of the
measured workload for every competitor (as in `3dpoc.py`); `--no-hud` removes it.

## Frame-time lows

`1% low`, `0.1% low` and `0.01% low` are the **average frame rate of the slowest X% of frames**
(k = max(1, ceil(X% x frames)) frames); `min` is the single slowest frame. Frame time is the interval between
consecutive frame callbacks, so it covers CPU and GPU throughput together. With 10 000 frames, 0.1% = the worst 10
frames and 0.01% = the worst 1, i.e. equal to `min` (for runs under 10 000 frames too, because k never drops below
1) - so below 10 000 frames the 0.01% figure is just the worst frame. Only the slowest 1% of frames are kept in a
small sorted array (`frame_stats.gd`, unit-tested against a brute-force sort), so tracking costs one comparison
per frame. The overlay's own text update happens every 15 frames and is included in the frame times; use
`--no-hud` for the cleanest lows. The final `complete` event carries the same numbers:

```
"frame_stats": {"avg_fps":..., "low_1_fps":..., "low_0_1_fps":..., "low_0_01_fps":..., "min_fps":..., "worst_frame_ms":...}
```
They are informational; the score is still `best_ms`. A percentile definition (frame time at the 99.9th percentile)
is a one-line change in `frame_stats.gd` if you prefer it.

## Single-file build (what competitors download)

An exported build is **one executable** (~580 MB) with the engine, the level, the route and the robots inside. It
leaves out everything else in the 1.4 GB working folder (`.git`, `.blend` sources, raw PNGs, import cache, the
record/bake/export tools). It is produced by `scripts/build.sh` (see above); the steps it automates are:

```bash
scripts/setup.sh tps-bench
godot --headless --path tps-bench --import
godot --headless --path tps-bench --script res://ocgp_bench/export_list.gd -- --no-lightmap
godot --headless --path tps-bench --export-release "Windows Desktop" build/OCGP-TPS.exe
```

Run it: `OCGP-TPS.exe --rendering-driver vulkan --disable-vsync --fixed-fps 60 --flush-stdout -- --variant Medium --output result.txt`
(no scene argument; the exe starts the benchmark itself) or through the wrapper:
`python tps_wrapper.py --exe OCGP-TPS.exe --variant Medium`. Testers get `OCGP-TPS-tester.zip`, whose
`run_benchmark.bat` passes the required engine flags. Only the one exe needs hashing for the allowlist.

**Lean build.** The default build leaves out the lightmap GI data (~98 MB: `level.lmbake` and its EXR atlas), which
only `--gi lightmap` uses; that mode is refused with `gi_unavailable`. Drop `--no-lightmap` in `build.sh` for the full
build (~50 MB larger). The pack is dominated by textures (350 MB), baked VoxelGI data (39 MB) and meshes (29 MB); the
engine adds ~104 MB. Capping the four 4K textures at 2K would save ~64 MB but changes the visuals; not done.

**No music.** The benchmark has no audio (the level's `Music` node is removed at load and the audio bus is muted), so
`patches/level.tscn.patch` removes the stream reference and `level_music.ogg` is not shipped. `build.sh` fails if it
ever appears in the exe.

Why `export_list.gd` exists: the exporter does not follow a script's `preload()` of another script or scene, the
external materials of an imported `.glb`, or project-setting resources (audio bus layout), so a naive export crashes at
runtime with missing files. It walks the dependencies and reads the scripts for `res://` paths, and lists all of it.

Caveats: the exe is a GUI-subsystem build (no console), so use `--output FILE`, the wrapper, or redirect stdout
(`> run.txt`). A relative `--output` path is resolved against the **exe's folder**, not the current folder. No PCK
encryption (that needs a custom engine build, and CC-BY forbids technical restrictions on recipients anyway): hash the
exe instead. The route and robots are baked in at export time, so re-export after re-recording or re-baking.

## Events

```
{"event":"start","workload":"tps","variant":"Medium","total_sectors":10,"frames":10000,"gi":"voxel",...,"adapter":"<GPU>","godot":"4.7.2-stable (official)"}
{"event":"sector","iter":1,"sector":1,"total_sectors":10,"sector_ms":123.45}
{"event":"complete","best_ms":<sum of sector_ms>,"sector_times":[...],"total_sectors":10,"frames":10000,"frame_stats":{...}}
```
Errors: `{"event":"complete","error":"<code>","message":"..."}`. Every field, the integrity checks and the full list of
error codes are in [`OUTPUT.md`](OUTPUT.md). With `--output FILE` the same lines are also written to the file.

## Licensing — read before shipping to competitors

* Demo **assets: CC-BY 3.0** (© 2018 Juan Linietsky, Fernando Miguel Calabró). Attribution is required wherever they
  are redistributed, the adaptation must be flagged as modified, and recipients' rights may not be restricted
  (so: no encrypted pack). `NOTICE.md` carries all of this and is attached to every release.
* The demo's **music** (CC-BY 3.0, © 2018 Christian Fernando Perucchi) is not included in the exe.
* The demo's LICENSE also notes many Substance Painter materials were provided by **GameTextures.com**; the demo's
  authors distribute the finished assets under CC-BY 3.0. Upstream clearance of the underlying materials is not
  independently verified.
* Demo **code: MIT** (© 2018-2021 Juan Linietsky, Godot Engine contributors). `level_static.gd` is derived from
  `level.gd` and keeps that notice. The exe embeds the Godot Engine (MIT).
* The licence of the OCGP overlay code itself is not decided yet.

## Status / known issues

Verified (Godot 4.7.2, Windows, RTX 4090): clean build from an empty folder via `scripts/build.sh`; the exported exe
runs all 10 sectors and emits the event stream; `--variant` / `--output` including error cases; the Small variant
completes in about 30 s there. Earlier: fixed-timestep guard, headless event stream, software-Vulkan (llvmpipe) frames.

**Not verified:** the GitHub Actions workflow (first run pending), timings on other GPUs, run-to-run variance, whether
the scene is GPU- rather than CPU-bound at 1080p, shader-compile/pipeline-cache effects on the first timed sector, and
cross-vendor behaviour.

* **Headless import crashed** (segfault in a worker thread on `level/geometry/models/*.glb`) in a 1-core / 4 GB
  sandbox. Workaround used for testing only: disable LOD / shadow-mesh / lightmap-unwrap generation in those four
  `.glb.import` files. On a normal machine the stock import settings should be used — report back if it crashes
  (CI will show this).
* The demo's `project.godot` selects Wayland on Linux and requests HDR output; the benchmark overrides HDR at
  runtime. This repo only targets Windows for now.
* `known_hashes` in the committed `manifest.json` is empty (unverified); release builds ship a stamped copy.
* Frame counts of the variants (Small/Medium 10 000, Large 5 000) are guesses; tune once real GPU speeds are known.
  They live in two places that must agree: `manifest.json` and `VARIANTS` in `ocgp_bench/bench.gd`.
* The exe is not byte-reproducible (two builds of the same sources differ), so always use the hash of the released file.
* Sector timing uses CPU timestamps; GPU work is queued a few frames deep, so each boundary can blur by ~2-3
  frames. The sum is unaffected except for the tail of the last sector (negligible at these sizes).
