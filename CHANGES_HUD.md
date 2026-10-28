# HUD / overlay changes (2026-10-20)

Visual-only changes to `ocgp_bench/bench.gd`. None of this affects timing, scoring, or the
event protocol (`start` / `sector` / `complete`) — it's display layer only.

## What changed

1. **Professional-looking stats HUD.** The live readout (frame/sector counters, fps, lows)
   now sits inside a rounded, semi-transparent panel (`hud_panel`) instead of floating bare
   text over the scene.
2. **Bottom credit overlay.** A persistent, centered, two-line credit at the bottom of the screen
   (`credit_label`, text in `CREDIT_TEXT`): the OC Grand Prix line, then the Godot TPS demo attribution
   (assets CC-BY 3.0 modified; code MIT; Godot Engine MIT). Update the OCGP rights holder/year there if it changes.
3. **Sector title, top right.** The current sector's in-universe title (e.g. "Sector 1 : Entrance Hall") stays in a
   panel in the top-right corner for the whole sector. Titles live in `SECTOR_TITLES` (index wraps like `VANTAGES`).
4. **HUD panel auto-sizes.** The GPU name is on its own line and the panel grows to fit its text (`_fit_hud_panel`).

All overlays are created in `_setup_hud()` and are suppressed together by `--no-hud`.

## Rebuild required

`bench.gd` is packed into the exported Godot project. These changes only show up in:

- The Godot editor, next run.
- A re-exported `.exe`, after running the export (see `scripts/build.sh` / the GitHub Actions
  build workflow) — any previously built exe on disk or in a release is stale and will not
  show the new overlays until re-exported.

This repo has no checked-in `.exe` or `export_presets.cfg` at the moment, so there's nothing
stale to clean up yet — but remember this the next time a build is cut.
