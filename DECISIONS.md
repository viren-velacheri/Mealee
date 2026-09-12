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
