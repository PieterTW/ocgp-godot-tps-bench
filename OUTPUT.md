# TPS benchmark output - what a run reports

For OCGP to decide which data to capture. The benchmark prints **one JSON object per line** on stdout (via
`tps_wrapper.py`, which relays only these lines), and the exe can also write the same lines to a file with
`--output FILE` (a relative path is resolved against the exe's folder). Same protocol as `3dpoc.py`:
`start` -> `sector` x N -> `complete`.

```
{"event":"start", ...}
{"event":"sector","iter":1,"sector":1,"total_sectors":10,"sector_ms":68.04}
...
{"event":"complete","best_ms":557.26,"sector_times":[...],"total_sectors":10,"frames":200,"frame_stats":{...}}
```

If a run cannot be scored it ends with `{"event":"complete","error":"<code>","message":"..."}` and exit code 1.

## Score

**`complete.best_ms`** = sum of the sector times in ms. **Lower is better.** `sector_times` (same values, one per
sector) are the per-sector splits, and each `sector` event carries one of them live, which is what a race UI can show
as progress. `iter` is always 1 (single pass). A run's score is only valid if `debug_run` is false.

## `start` event

Emitted once, when the timed part begins (after warmup).

| Field | Example | Use |
|---|---|---|
| `workload` | `"tps"` | identify |
| `variant` | `"Medium"` (`""` if frames/res were given by hand) | **verify** it matches the variant the server requested |
| `frames`, `total_sectors` | `25000`, `10` | **verify** against the variant table in `manifest.json` |
| `resolution`, `render_size` | `"1080p"`, `[1920,1080]` | **verify** `render_size` matches the variant (the window can be smaller) |
| `warmup` | `300` | informational |
| `gi`, `gi_quality` | `"voxel"`, `"high"` | **verify** defaults (`voxel`/`high`); other profiles are not comparable |
| `path_sha256` | hex | **verify** equals the published route hash (competitors must not alter the route) |
| `activity_sha256`, `activity_robots` | hex, `18` | **verify** equals the published robot-layout hash |
| `camera_path`, `path_samples`, `player` | `"recorded"`, `1590`, `true` | **verify** `recorded` / `true`; `"vantages"` means the route file was missing |
| `sim_step` | `0.016667` | informational (a wrong timestep aborts the run) |
| `rendering_driver`, `rendering_method` | `"vulkan"`, `"forward_plus"` | **verify** driver is `vulkan` (pinned for comparability) |
| `adapter` | `"NVIDIA GeForce RTX 4090"` | **record**: GPU name, useful for leaderboards and cross-checking telemetry |
| `godot` | `"4.7.2-stable (official)"` | **verify** against the allowlist |
| `vsync`, `hdr_output`, `hdr_2d` | `0`, `false`, `true` | informational |
| `debug_run` | `false` | **reject the result if true** (a debug option was used) |
| `fingerprints` | `{"exe":"<sha256>"}` | added by `tps_wrapper.py`; **verify** against `known_hashes` (the wrapper already refuses unknown hashes) |

## `sector` event

`sector` (1..`total_sectors`), `total_sectors`, `sector_ms` (float, 2 decimals), `iter`. With the debug option
`--profile` it also has a `profile` object, but such runs are `debug_run: true` and not submittable.

## `complete` event (success)

| Field | Use |
|---|---|
| `best_ms` | **the score** |
| `sector_times` | per-sector splits (sum equals `best_ms`) |
| `frames`, `total_sectors` | echo; **verify** equals the `start` event |
| `debug_run` | present (true) only for debug runs; **reject** if present |
| `frame_stats.avg_fps` | informational: average frame rate over the whole run |
| `frame_stats.low_1_fps`, `low_0_1_fps`, `low_0_01_fps` | informational: average fps of the slowest 1% / 0.1% / 0.01% of frames |
| `frame_stats.min_fps`, `worst_frame_ms` | informational: the single slowest frame |

`frame_stats` is not part of the score; it is useful for stutter display, tie-breaks, or anomaly checks (e.g. a
run whose `avg_fps` is inconsistent with `best_ms`).

## `complete` event (error)

`{"event":"complete","error":"<code>","message":"<text>"}` - treat as DNF.

| `error` | Meaning |
|---|---|
| `fixed_timestep_required` | engine flags missing (`--fixed-fps 60 --disable-vsync`); the wrapper always passes them |
| `canvas_size_invalid` | internal render size is not the variant's size |
| `invalid_args` | bad `--variant`/`--res`/`--frames`/`--sectors` (or `--variant` mixed with the others) |
| `gi_unavailable` | `--gi lightmap` requested but this build does not include lightmap data |
| `invalid_path`, `invalid_activity`, `activity_path_mismatch` | route / robot data missing or inconsistent |
| `output_unwritable` | `--output` file could not be created |
| `execution_failed` | added by `tps_wrapper.py`: the process exited without a `complete` event (crash) |
| `unrecognized_files` | added by `tps_wrapper.py`: exe hash not in `known_hashes`; carries `fingerprints` |
| `godot_not_found`, `project_not_found` | added by `tps_wrapper.py`: nothing to run |

## Suggested for OCGP to capture

1. **Per run:** `best_ms`, `sector_times`, `variant` (and `frames`/`render_size` as a cross-check), `adapter`,
   `fingerprints.exe`, `godot`.
2. **Integrity gate (reject if any fails):** `debug_run` is false/absent, `path_sha256` and `activity_sha256` match
   the published values, `rendering_driver == "vulkan"`, `camera_path == "recorded"`, `player == true`, exe hash in
   `known_hashes`.
3. **Live display:** each `sector` event (`sector` / `total_sectors`, `sector_ms`) as race progress.
4. **Optional extras:** `frame_stats` for stutter/lows display and anomaly detection.

Not currently reported (would need a change in the benchmark): GPU/CPU clocks, temperatures or power during the run -
OCGP's own telemetry plugins cover those. The wrapper discards stderr and non-JSON stdout lines.
