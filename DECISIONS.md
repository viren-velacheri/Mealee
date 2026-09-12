# Decisions

One line per non-obvious choice: what was chosen over what, and why.

- Three stores over one: SQLite for hot game state, Atlas for player identity, Redis for
  realtime. A single store would either put the 4 s photo path behind a network hop or
  give up the sponsor integrations.
- Redis pub/sub over in-process WebSocket broadcast: the arena page and the phones may be
  served by different workers once deployed, and an in-process set of sockets does not
  survive that. Falls back to in-process if `REDIS_URL` is unset, so local dev needs nothing.
- Redis stores nothing: the live-fight key was written on every fight and read by nothing
  (the arena polls SQLite), so it was removed rather than wired in. Fewer commands on the
  hot path, and the 29 MB plan is never written to.
- Atlas writes are fire-and-forget off the request path: an Atlas timeout must never fail a
  meal upload or a fight. Identity is recoverable, a dropped demo is not.
- Auth0 added despite the original "no auth" scope line: explicit call by the team. It is
  gated behind `AUTH0_ENABLED` in `Config.xcconfig` so a failing login can be switched off
  at the venue without a code change.
- Battle simulation written twice, Python and Swift, rather than shared: the phone must
  replay a fight offline from a seed, and `MockAPI` must generate fights with no server.
  A unit test pins the two implementations to identical logs on three fixture seeds.
- mulberry32 over the language RNGs: `random` and `SystemRandomNumberGenerator` give
  different streams from the same seed, which would break the cross-language determinism test.
- Integer math in the simulation damage roll: floating point drift between Python and Swift
  would fail the log equality test after enough turns. Damage is computed in thousandths and
  divided once at the end.
- Portion band fixed at +/-30% rather than derived from mask confidence: an honest wide band
  reads better to judges than a precise-looking number we cannot defend.
- Douglas-Peucker to under 40 points per polygon: the phone draws these every frame during
  the scan animation, and raw masks run to hundreds of points.
- Vision fallback has a 1.5 s timeout and is skipped on expiry, keeping the YOLO label: the
  4 s budget is the demo, one unlabelled region is not.
- XcodeGen `project.yml` over a hand-written pbxproj: a pbxproj written blind with an SPM
  dependency is the likeliest thing to be broken on first open. Commit the generated
  project after the first `xcodegen generate` so teammates never need the tool.
- Fruit is not counted as vegetables for defense: the target is 400 g of vegetables and an
  apple-only day should not read as well defended. Beans count.
- Standings count quick matches as well as nightly fights: a quick match at the expo should
  move the projector standings immediately, and nobody at a hackathon farms wins.
- Minimum mask size is 1% of the image, not 1% of the plate: plate detection is another
  detector to get wrong, and the intent is only to drop crumbs.
- `nutrients_fallback.yaml` ships alongside `foods.yaml`: USDA cannot be downloaded from the
  build container, and a failed Friday download must not take the meal path down. The
  server warns on every start it runs without `usda.sqlite`.
- Home shows weekly wins rather than a daily win/loss record: the API reports wins per week
  in standings and nothing per day, and adding a per-day endpoint is a feature not asked for.
- Fixtures for `MockAPI` are captured from the real server (`tools/make_ios_fixtures.py`)
  rather than typed: the phone then decodes exactly what the server sends.
- Combat stats are truncated with `int(x + 0.5)` on both sides, never `round()`: Python
  rounds half to even and Swift rounds half away from zero.
- Empty error handling on `/meals` narrowed to unreadable images: a missing dependency or a
  bug in the CV path surfaces as a 500 in the log rather than a "bad photo" hint to the player.
- A missing card or fork uses an explicitly `estimated` scale based on a tightly framed 300 mm
  scene: classification should still work for bowls, while the UI remains honest that grams are approximate.
- COCO `cup` detections are ignored rather than mapped to coffee: a container does not identify its
  contents, and coffee can be logged explicitly with the intake control.
- Scanned meals remain `draft` until the review screen confirms them: Retake and Cancel must not
  quietly change fighter stats or Foodex discoveries, and the existing meal status field provides
  that boundary without attempting to roll back already-published game state.
- try/finally and a narrow except inside `realtime.py` despite the "catch only at route
  boundaries" rule: a WebSocket hold-open loop only ever exits by exception, so the
  teardown that releases the Redis subscription has to live in a finally. Without it every
  closed socket leaked one pooled connection and the worker died at 100. Verified against a
  real local Redis; `tests/test_realtime.py` pins it.
- Publish is best effort and serialized: it runs after the SQLite commit, so raising would
  return a 500 for a saved row, and a half-open Redis would stall the 4 s photo path. The
  lock keeps the pool at one publisher connection, which matters against Redis Cloud's
  per-plan connection cap. socket_timeout is 1 s for the same reason.
- A dead pub/sub subscription closes the client socket (1012) instead of retrying inside
  the server: the arena and the phone already reconnect on close, and a socket that
  answers pings but never delivers is the worst failure mode at an expo.
- One uvicorn worker in production: the nightly scheduler is per process, and Redis
  Cloud's connection cap is per plan, not per worker. Railway runs one replica.
- One immediate Redis retry, no backoff: after a failover an idle pooled connection still
  reports connected and fails on first use, which lost the first publish after every
  restart. One retry fixes that at no cost; a backoff would add latency to the photo path
  during a real outage, when publish is best effort anyway.
- Ink `#1E2A22` added to the five-swatch palette: all five are light, and readable text
  needs one deep tone. It is sage taken down to 15% lightness, so it still belongs.
- SwiftUI Metal shaders (`colorEffect`, `distortionEffect`) over Core Animation tricks for
  the aurora, liquid meters, the photo dissolve and the ripple transition: they are
  first party, iOS 17, and cost one GPU pass each; no dependency, no UIKit bridging.
- The photo is eaten by a dissolve shader instead of a particle system: it delivers the
  "bite" moment the spec wants in one draw call and stays fluid on the oldest demo phone.
- Reasons hidden behind "Why" on Home: the screen is calmer and the numbers land first;
  the reasons stream in on demand, which makes them feel earned rather than dumped.
- Fight starts by swiping the chosen rival up into the ring, with a button as the fallback:
  the gesture is the delight, the button is the guarantee.
- Rounded SF for anything that carries weight, plain SF for body: one family, two voices.
- The liquid transition keeps scale, blur and opacity but drops its ripple
  distortionEffect: a Metal distortion cannot rasterize a subtree holding TextFields,
  ScrollViews, a TabView or .ultraThinMaterial, so on device SwiftUI drew its shader
  failure placeholder (yellow field, red prohibitory sign) over every screen. Shader
  effects now only wrap plain shapes and images, where they work.
- The join screen never disables its buttons. A disabled pill says "no" without saying
  why; a tap that names the one missing thing ("Enter your name first...") teaches the
  flow in one step. The rules live in JoinForm so the wording is pinned by tests.
- Connection failures are translated at the API boundary into one instruction, "Check
  that this phone and the Mac running the server are on the same network", because a
  dead server, a blocked network and a timeout are indistinguishable to the player and
  have the same fix.
- Manual food correction uses USDA FoodData Central search rather than Querit web search:
  fighter stats need structured nutrient values tied to stable FDC IDs, while Querit returns
  general web content. The camera still makes no open-ended or language-model decision.
- Mixed bowls are split manually in review rather than pretending the segmenter can see hidden
  ingredients: each searched ingredient has its own grams and nutrient contribution before Confirm.
- Custom avatars accept any single emoji rather than uploading images: player, fight, league, and
  arena payloads already render an emoji everywhere, so this expands choice without adding media storage.
- The fight is staged like a creature battle rather than two stat cards: the opponent
  sits high and small, you sit low and large, and depth is faked with scale and offset
  alone. It reads as one scene, which two glass panels never did.
- A fighter is the food emoji with four squiggly limbs and nothing else. No body shape
  competes with the food, and a stroked sine wave costs one Path per limb.
