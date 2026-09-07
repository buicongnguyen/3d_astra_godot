"""Verify release downloads against hashes checked into this repository."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parents[1]
expected = dict(line.split(maxsplit=1)[::-1] for line in (root/'tools/godot-checksums.txt').read_text().splitlines() if line.strip())
for local, original in [('engine.zip','Godot_v4.7.2-stable_linux.x86_64.zip'),('templates.tpz','Godot_v4.7.2-stable_export_templates.tpz')]:
    with (root/'.tools'/local).open('rb') as stream:
        actual = hashlib.file_digest(stream,'sha512').hexdigest()
    if actual != expected[original].strip(): raise SystemExit('Checksum mismatch: '+original)
    print('Verified '+original)
