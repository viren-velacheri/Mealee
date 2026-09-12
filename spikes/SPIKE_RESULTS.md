# Spike results

Written 2026-09-12 from a Linux build container with no macOS, no Xcode, no iPhone,
no plate photos, and an egress proxy that blocks the YOLO weights host and USDA.
Everything marked "not run" is written and ready to run on the team Mac.

| Spike | Result | Evidence |
|---|---|---|
| 1. Card scale reference | **NOT RUN** on real photos. Detector found a drawn card at 4.16 px/mm against a ground truth of 4.206 (1.1% error) on the synthetic fixture plate. | `server/tools/make_ios_fixtures.py` output. A drawn card is a far easier target than a photographed one; this proves the code path, not the accuracy claim. |
| 2. YOLO segmentation | **NOT RUN**. No photos, and `yolov8s-seg.pt` cannot be downloaded from here. | `spikes/spike_seg.py` is ready. Needs 5 plate photos in `spikes/photos/`. |
| 3. Battle sim, Python and Swift agree | **PASS** in both languages. | `python3 spikes/spike_battle.py` passes. `BattleSimTests.swift` compiled and ran under Swift 6.0.3 on Linux: 4 tests, 0 failures, turn logs identical for all three fixture seeds. mulberry32 verified byte for byte against the canonical JavaScript under Node. |
| 4. Hello world on every iPhone | **NOT RUN**. Impossible without Xcode and cable. | Do this Friday night. See `ios/README.md`. |

## What to do on the Mac, in order

1. Take 5 photos of real plates with a credit card in frame. Put them in `spikes/photos/`.
   Measure the card's long edge in pixels in Preview for at least 3 of them and write
   `spikes/photos/measured.json` as `{"IMG_0001.jpg": 4.31}` (pixels / 85.6).
2. `make install` then `make spikes`. Spike 1 passes if every measured photo is within 10%.
   Spike 2 prints what YOLO found; judge by eye or add `expected.json`.
3. **If spike 1 or 2 fails, stop and talk before building on the CV path.** The fallbacks
   are: fork instead of card (already supported, lower confidence), and a fixed
   px_per_mm from a known phone height as a last resort.
4. `python3 data/build_usda.py` to download USDA and build `data/usda.sqlite`. It prints
   what each `fdc_id` in `foods.yaml` resolves to. Read every line. The ids were entered
   from reference without a live check and some will be wrong.
5. iOS first build per `ios/README.md`. Expect a compile-error pass: every Swift file
   outside `BattleSim.swift`, `Models.swift`, `MealeeAPI.swift`, `LiveAPI.swift` and
   `MockAPI.swift` was written without a compiler.

## Verified in the container

- 27 server tests pass (`make test`): stat mapping, battle determinism, meal upload
  with stubbed segmentation, relabel, intake presets, quick match, replay from seed,
  standings, WebSocket events, error shapes.
- Seeded DEMO league serves standings, tonight's card, fighters with reasons, quick
  matches with sugar crashes, and the arena page.
- Swift battle simulation compiled and matched Python exactly.
- The Swift API layer (`Models`, `MealeeAPI`, `LiveAPI`, `MockAPI`) plus `AppState` and
  `FightViewModel` compiled on Linux against the JSON fixtures the server actually
  produced. Only the SwiftUI views, `MealReviewViewModel` (UIKit) and the Auth0 session
  remain uncompiled; each was re-read line by line for compile errors.
- The arena page driven in headless Chromium against the seeded server: standings
  render, a quick match animates turn by turn with HP bars and the correct winner, a
  Redis kill flips it to polling, it reconnects on its own when Redis returns, and the
  next fight plays through the new socket. No page errors. Screenshots under the
  session scratch directory.
- Realtime through a Redis failover, end to end: an attached client is closed with 1012
  within 0.2 s of Redis dying, POST /intake returns 200 in 10 ms during the outage, and
  a fresh subscriber receives the first publish after the restart.

## Not verifiable here

- Anything SwiftUI, AVFoundation, or Auth0.
- The Redis Cloud and MongoDB Atlas hosts themselves. The container's egress relay does
  not carry raw TCP to database ports (its README lists "raw-TCP databases" as
  unsupported), so both must be checked from a laptop or from Railway. The Redis *code*
  is verified: `realtime.py` was run against a real local `redis-server`, across two
  uvicorn workers, through a 25 s idle gap, and through 100 opened-and-closed sockets.
  That run found and fixed a connection leak on socket close (`tests/test_realtime.py`).
  Atlas code paths run with the env var unset (logged skip) and are not verified live.
- The IFM vision fallback (host blocked). It is off unless `IFM_API_KEY` is set.
