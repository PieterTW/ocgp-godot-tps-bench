"""Zip the tester package: exe + launcher + instructions + notice.

Usage: python scripts/package_testers.py <exe> <out.zip>
"""
import sys
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
exe, out = Path(sys.argv[1]), Path(sys.argv[2])
files = [
    (exe, "OCGP-TPS.exe"),
    (root / "tester" / "run_benchmark.bat", "run_benchmark.bat"),
    (root / "tester" / "TESTERS.md", "TESTERS.md"),
    (root / "NOTICE.md", "NOTICE.md"),
]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for src, name in files:
        if name.endswith(".bat"):   # cmd.exe wants CRLF whatever the checkout's line endings are
            z.writestr(name, src.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
        else:
            z.write(src, name)
print(f"{out} ({out.stat().st_size / 1e6:.0f} MB)")
