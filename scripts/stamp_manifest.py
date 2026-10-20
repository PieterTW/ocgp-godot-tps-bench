"""Write the built exe's sha256 into a release copy of manifest.json (known_hashes).

Usage: python scripts/stamp_manifest.py build/OCGP-TPS.exe <label> build/manifest.json
The committed manifest.json keeps known_hashes empty; the stamped copy is a release asset.
"""
import hashlib
import json
import sys
from pathlib import Path

exe, label, out = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
h = hashlib.sha256()
with exe.open("rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)
manifest = json.loads((Path(__file__).resolve().parent.parent / "manifest.json").read_text("utf-8"))
manifest["external_dependency"]["known_hashes"] = {h.hexdigest(): label}
out.write_text(json.dumps(manifest, indent=2) + "\n", "utf-8")
print(f"{h.hexdigest()}  {label}")
