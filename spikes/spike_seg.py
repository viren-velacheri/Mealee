"""Spike 2: run YOLO segmentation on plate photos, print labels and mask areas.

    cd server && uv run python ../spikes/spike_seg.py ../spikes/photos

First run downloads yolov8s-seg.pt (needs GitHub reachable). To auto-score, add
spikes/photos/expected.json: {"plate1.jpg": ["pizza slice", "salad greens"], ...}.
Pass is 3 of 5 plates with every expected label found. Without expected.json, read the
output and judge by eye, then record the verdict in SPIKE_RESULTS.md.
"""

import json
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "server"))

from app.portions import COCO_TO_FOOD, decode_image, segment


def main(photo_dir: pathlib.Path) -> int:
    photos = sorted(p for p in photo_dir.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png"))
    if not photos:
        print(f"no photos in {photo_dir}. Add 5 plate photos.")
        return 2
    expected = {}
    expected_path = photo_dir / "expected.json"
    if expected_path.exists():
        expected = json.loads(expected_path.read_text())

    print("Spike 2: YOLO segmentation\n")
    plates_ok = 0
    for photo in photos:
        image = decode_image(photo.read_bytes())
        image_area = image.shape[0] * image.shape[1]
        started = time.perf_counter()
        detections = segment(image)
        elapsed = time.perf_counter() - started
        print(f"  {photo.name}  ({elapsed:.2f}s, {len(detections)} masks)")
        labels_found = set()
        for name, confidence, mask in detections:
            share = mask.sum() / image_area
            mapped = COCO_TO_FOOD.get(name)
            labels_found.add(mapped or name)
            print(f"      {name:<14} -> {mapped or '(vision fallback)':<18} conf {confidence:.2f}  area {share * 100:4.1f}%")
        if photo.name in expected:
            missing = [label for label in expected[photo.name] if label not in labels_found]
            ok = not missing
            plates_ok += ok
            print(f"      {'ok' if ok else 'MISSING ' + ', '.join(missing)}")

    if expected:
        passed = plates_ok >= 3
        print(f"\nplates with all expected items: {plates_ok} of {len(expected)}")
    else:
        passed = None
        print("\nno expected.json. Judge by eye: are all major items on at least 3 of 5 plates found?")
    print(f"\nSPIKE 2: {'PASS' if passed else 'FAIL' if passed is False else 'NEEDS HUMAN VERDICT'}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "spikes/photos")))
