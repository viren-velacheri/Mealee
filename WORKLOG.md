# Work log

One entry per working session, newest last. What was done, what was verified, what is
open. Commit hashes refer to branch `claude/hopeful-mayer-q59x3p`.

## 2026-09-12, session 1: build

- Scaffold, `CLAUDE.md`, `DECISIONS.md`, `.gitignore`, `.env.example`. `9f9d35d`
- Battle simulation in Python and Swift with mulberry32, verified byte for byte against
  canonical JavaScript under Node; Swift 6.0.3 installed in the container, `BattleSimTests`
  compiled and passed on Linux with turn logs identical to Python. `b8fe74c`
- FastAPI server (routes per contract, SQLite, Redis pub/sub, Atlas mirror, IFM vision
  fallback, nightly job, seed, Dockerfile, Railway config), arena page, CV spikes,
  27 pytest tests. Seed bug found and fixed: history fights used today's fighter. `9262294`
- SwiftUI app through Layer 1 with `MockAPI`, `LiveAPI`, Auth0 via SPM, XcodeGen spec.
  API layer compiled on Linux; SwiftUI, AVFoundation and Auth0 files unverified. `587abb1`
- Open: spikes 1, 2, 4 need a Mac and photos. `fdc_id` values unverified against USDA.

## 2026-09-12, session 2: Redis and Auth0 checks

- Redis Cloud host unreachable from the container by every route. The egress relay drops
  raw TCP to database ports (its README lists "raw-TCP databases" as unsupported). Not a
  policy toggle; verify from a laptop or Railway.
- `realtime.py` verified against a real local `redis-server`: the socket_timeout worry
  was refuted with source evidence (redis-py 8.1.0 exempts pub/sub reads), but every
  closed WebSocket leaked one subscribed connection and a worker died at 100. Fixed with
  try/finally on both paths, 3 regression tests, 30 tests green. `84c9416`
- Auth0 tenant probed read-only with controls and an independent replication: client id
  valid, callback URL and logout URL both NOT configured. The Management API needs a
  token the native app cannot mint; routes documented in the chat.
- Auth0.swift 2.22 source check: the callback string in `ios/README.md` is byte for byte
  what the SDK sends; no `CFBundleURLTypes` needed; `CallbackMode` is a Mealee key, not
  an SDK key; the SDK needs Xcode 16+.
- Second verification pass on the fixed code (two workers end to end, memory and
  connections, source review, 220-socket churn with kill -9 and Redis restarts):
  cross-worker delivery holds, the leak is gone, and six further defects were found.
  See session 3.

## 2026-09-12, session 3: Redis hardening

- Fixed: best-effort publish after commit (a Redis outage no longer turns a saved meal
  into a 500); `_forward` closes the socket with 1012 on a Redis drop so clients
  reconnect; subscribe moved inside the try; `RedisError` handled in `league_socket`
  with a 1013 close; publish serialized under a lock with an explicit pool cap;
  idle timeout sends a proper close frame; nightly publish failures are logged;
  unused `mealee:live:*` key removed.
- iOS: `AppState` now reconnects the event stream after the server closes it.
- Found in the e2e failover run and fixed: the first publish after a Redis restart was
  lost because an idle pooled connection still reported connected. One immediate retry.
  Regression test added; e2e failover run passes (client closed 1012 on the drop,
  intake 200 during the outage, fresh subscriber receives after the restart).
- Open: Redis Cloud and Atlas still unverified live. Nightly job assumes one worker
  (Railway runs one).

## 2026-09-12, session 4: everything else

- No external changes on the remote branch (only `claude/hopeful-mayer-q59x3p` exists,
  tip was my previous commit). Redis work closed out and pushed.
- Arena page verified in headless Chromium through a fight and a Redis failover, see
  `spikes/SPIKE_RESULTS.md`. The only console 404 is the browser asking for
  `/favicon.ico`; no route exists and none is needed on a projector.
- `AppState` and `FightViewModel` compile on the Linux Swift toolchain (Observation is
  available there). All seven SwiftUI views re-read for compile errors; none found, but
  they remain uncompiled until Xcode.
- Open, unchanged: spikes 1, 2, 4 need the Mac and photos; `fdc_id` values need the USDA
  verify step; Redis Cloud and Atlas need a live check from a laptop; Auth0 callback and
  logout URLs are still unset in the dashboard.
