# Next steps / open items

Last updated 2026-10-20. Tick items off (or delete them) as they are settled.

## Open decisions

- [ ] **OCGP integration.** How does OCGP fetch the exe? Candidates: a GitHub release asset (needs the repo to be
  public, or an authenticated download), a URL in the manifest, or `~/.ocgp/external/` as for the other workloads.
  Once decided, `oc-grand-prix` needs a `workloads/tps/` folder with the stamped `manifest.json`, `tps_wrapper.py`
  and an `about.md`. Nothing has been changed in `oc-grand-prix` so far.
- [ ] **What OCGP captures.** `OUTPUT.md` lists every field and a suggested capture / integrity-check list. OCGP
  to confirm or adjust.
- [ ] **Licence for the overlay code.** Suggested: all rights reserved with the OCGP header (keeps competitors from
  casually forking the benchmark); alternative: MIT. Then add a `LICENSE` and the headers. `level_static.gd` keeps its
  MIT notice either way, and the assets stay CC-BY 3.0 (see `NOTICE.md`).
- [ ] **Public or private repo.** Currently private. Going public needs the licence decision above and the final
  route / robot data.
- [ ] **GameTextures.com materials.** The demo credits them for the original materials; the demo's authors release the
  finished assets under CC-BY 3.0. Not independently cleared. Optionally ask the demo's maintainers or GameTextures.

## Benchmark content

- [ ] **Finalize `route.ocgp` and `activity.ocgp`** (not final yet). Re-recording the route means re-baking the
  robots (`activity.ocgp` stores the route's hash), then rebuilding and republishing the hashes. See README.
- [ ] **Tune the variants.** Frame counts (Small/Medium 10 000, Large 5 000) are guesses. They live in two places that
  must agree: `manifest.json` and `VARIANTS` in `ocgp_bench/bench.gd`. Needs full runs on several GPUs.
- [ ] **Measure run-to-run variance.** One RTX 4090 gave 27 064 ms and 26 746 ms on two Small runs (about 1.2 %).
  Collect more from the testers.
- [ ] **Check GPU- vs CPU-bound at 1080p** (`--profile` shows `gpu_ms` against `frame_ms`), and shader-compile effects
  on the first timed sector.

## Build and release

- [ ] **Run the GitHub Actions workflow for the first time** (Actions tab > build > Run workflow, or push a `v*` tag).
  Untested parts: the Godot and export-template download URLs, the template extraction path, the asset import on the
  runner, and the 580 MB artifact upload. Fix anything it turns up.
- [ ] **First real release.** After the workflow works: tag `v0.1.0`. The release carries the exe, its sha256, the
  stamped `manifest.json` (`known_hashes` filled in), the tester zip and `NOTICE.md`.
- [ ] **Add a build id to the `start` event.** Result files do not say which build produced them (the exe hash is only
  added by the wrapper). Would make tester results traceable.
- [ ] **In-exe credits.** CC-BY attribution currently ships as `NOTICE.md` next to the exe. Consider also printing it
  (for example in the `start` event) so it travels with the exe alone.
- [ ] **Code signing.** The exe is unsigned, so testers see SmartScreen warnings and some antivirus may flag it.

## Testing

- [ ] **Tester round 1** (build 2026-10-20, shared by Google Drive): collect the result files and system details,
  and look at variance, crashes, vendors other than NVIDIA, and Vulkan-driver problems.

## Housekeeping

- [ ] Delete the old `C:\Users\elmor\Documents\CodeProjects\tps-bench` folder (a locked `build/` was left over).
  The old run logs were saved to `CodeProjects\tps-bench-old-logs`.
- [ ] Fix SSH access to GitHub (`ssh -T git@github.com`) so a normal `git push` works; pushes currently go over HTTPS
  through `gh`.
- [ ] The exported exe is not byte-reproducible (two builds of identical sources differ), so always use the hash of the
  released file.
- [ ] The headless asset import crashed in a 1-core / 4 GB sandbox (see README, known issues). Watch for it on the CI
  runner.

## Done

- Repo created from the OCGP overlay with a scripted build (`scripts/build.sh`), verified from an empty folder.
- Windows-only export; music removed from the exe.
- `--variant` / `--output` options, tester package and launcher (`tester/`), `OUTPUT.md`.
- README and `NOTICE.md` (CC-BY 3.0 / MIT attribution, modified-version statement).
