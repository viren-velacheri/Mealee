# Decisions

One line per non-obvious choice: what was chosen over what, and why.

- Three stores over one: SQLite for hot game state, Atlas for player identity, Redis for
  realtime. A single store would either put the 4 s photo path behind a network hop or
  give up the sponsor integrations.
- Redis pub/sub over in-process WebSocket broadcast: the arena page and the phones may be
  served by different workers once deployed, and an in-process set of sockets does not
  survive that. Falls back to in-process if `REDIS_URL` is unset, so local dev needs nothing.
- Redis keys all carry a TTL: the plan caps at 29 MB, so nothing durable may accumulate there.
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
