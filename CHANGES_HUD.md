# HUD / overlay changes (2026-10-20)

Visual-only changes to `ocgp_bench/bench.gd`. None of this affects timing, scoring, or the
event protocol (`start` / `sector` / `complete`) — it's display layer only.

## What changed

1. **Professional-looking stats HUD.** The live readout (frame/sector counters, fps, lows)
   now sits inside a rounded, semi-transparent panel (`hud_panel`) instead of floating bare
   text over the scene.
2. **Bottom credit overlay.** A persistent, centered line at the bottom of the screen
   (`credit_label`, text in `CREDIT_TEXT`) for legal attribution. Update the name/year there
   if ownership or licensing terms change.
3. **Per-sector title cards.** Each sector briefly shows an in-universe title (e.g.
   "Sector 1 : Entrance Hall") centered on screen, fading out after
   `SECTOR_TITLE_FRAMES + SECTOR_TITLE_FADE_FRAMES` frames. Titles live in the
   `SECTOR_TITLES` array in `bench.gd` — edit the strings there to rename sectors (index
   wraps the same way `VANTAGES` does if `sectors > SECTOR_TITLES.size()`).

All three overlays are created in `_setup_hud()` and are suppressed together by `--no-hud`.

## Rebuild required

`bench.gd` is packed into the exported Godot project. These changes only show up in:

- The Godot editor, next run.
- A re-exported `.exe`, after running the export (see `scripts/build.sh` / the GitHub Actions
  build workflow) — any previously built exe on disk or in a release is stale and will not
  show the new overlays until re-exported.

This repo has no checked-in `.exe` or `export_presets.cfg` at the moment, so there's nothing
stale to clean up yet — but remember this the next time a build is cut.
