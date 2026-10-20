# OCGP TPS benchmark - tester build

A GPU benchmark: it flies a fixed route through a game level and measures how long a fixed number of frames takes.
**Lower total time is better.** Thank you for testing!

## Run it

1. Unzip everything into one folder (the exe is ~580 MB).
2. Double-click `run_benchmark.bat`, or from a terminal:

   ```
   run_benchmark.bat Medium
   run_benchmark.bat Small  my_result.txt
   run_benchmark.bat Large
   ```

| Variant | Render resolution | Frames |
|---|---|---|
| Small | 1280x720 | 10 000 |
| Medium (default) | 1920x1080 | 10 000 |
| Large | 3840x2160 | 5 000 |

A window opens, shows a live overlay (frame time, fps, 1% / 0.1% lows) and closes when finished. Don't touch the
window or run other heavy programs while it runs. The Large variant renders at 4K internally even on a 1080p monitor.

## What to send back

The result file (`ocgp_tps_result_<variant>.txt`, plain text, one JSON line per event) plus:

- GPU, CPU, driver version, RAM
- whether the GPU or CPU was overclocked
- anything odd (stutter, a crash, a blank or frozen window, a very long run)

The result file contains the GPU name and benchmark timings only.

## Notes

- Needs a GPU with **Vulkan** support (any recent driver).
- Windows SmartScreen may warn about an unknown publisher (the exe is not code-signed): More info > Run anyway.
- The last line of the result file should be `{"event":"complete","best_ms":...}`. If it contains `"error"`, send it
  back too - it explains what went wrong.
- Run each variant a few times if you can; run-to-run variance is one of the things being measured.
- Advanced: the exe itself takes `--variant Small|Medium|Large` and `--output FILE`, but it also needs
  `--rendering-driver vulkan --disable-vsync --fixed-fps 60` or it will refuse to score. A relative `--output` path is
  resolved against the exe's folder, not your current folder.
