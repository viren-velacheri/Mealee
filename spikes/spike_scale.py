"""Spike 1: find a credit card in each photo and print px_per_mm.

    cd server && uv run python ../spikes/spike_scale.py ../spikes/photos

Put 5 plate photos with a card in spikes/photos/. To score error, add
spikes/photos/measured.json: {"plate1.jpg": 4.31, ...} with px_per_mm measured by hand
(card long edge in pixels / 85.6). Pass is every scored photo within 10%.
"""

import json
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "server"))

from app.portions import decode_image, find_card_px_per_mm

PASS_TOLERANCE = 0.10


def main(photo_dir: pathlib.Path) -> int:
    photos = sorted(p for p in photo_dir.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png"))
    if not photos:
        print(f"no photos in {photo_dir}. Add 5 plate photos with a credit card in frame.")
        return 2
    measured = {}
    measured_path = photo_dir / "measured.json"
    if measured_path.exists():
        measured = json.loads(measured_path.read_text())

    print("Spike 1: credit card scale reference\n")
    found, scored_ok, scored = 0, 0, 0
    for photo in photos:
        started = time.perf_counter()
        px_per_mm = find_card_px_per_mm(decode_image(photo.read_bytes()))
        elapsed = time.perf_counter() - started
        if px_per_mm is None:
            print(f"  {photo.name:<24} NOT FOUND   ({elapsed:.2f}s)")
            continue
        found += 1
        line = f"  {photo.name:<24} {px_per_mm:6.2f} px/mm  ({elapsed:.2f}s)"
        if photo.name in measured:
            scored += 1
            error = abs(px_per_mm - measured[photo.name]) / measured[photo.name]
            ok = error <= PASS_TOLERANCE
            scored_ok += ok
            line += f"  measured {measured[photo.name]:.2f}  error {error * 100:4.1f}%  {'ok' if ok else 'OFF'}"
        print(line)

    print(f"\nfound card in {found} of {len(photos)}")
    if scored:
        print(f"within 10%: {scored_ok} of {scored}")
        passed = scored_ok == scored and found >= min(5, len(photos))
    else:
        print("no measured.json, cannot score error. Measure the card in 5 photos and add it.")
        passed = found >= min(5, len(photos))
    print(f"\nSPIKE 1: {'PASS' if passed else 'FAIL'}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "spikes/photos")))
