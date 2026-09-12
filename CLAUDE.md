# Mealee

Native iOS game built at HackCMU 2026, Food track. Your meals become your fighter.
Photograph a plate with a fork or credit card in frame for scale, the app measures the
food and turns the day's nutrients into six fighter stats, then players battle friends
in a deterministic auto-battle with a replayable turn log.

The technical claim made to judges: the photo-to-stats path is computer vision plus
geometry plus real nutrient data, and the fight is a simulation we wrote.

## Hard rules

- **No language model in any decision path.** A vision model is used for exactly one
  thing: naming a food region the segmenter could not classify, as a constrained choice
  from the `foods.yaml` class list. Never free text. Turn log notes are template strings.
- **Do not refactor working code.** Do not add features not listed in the build plan.
  If something seems missing, ask.
- Small, plain code. No abstraction used once, no wrapper types, no protocol hierarchy
  beyond `MealeeAPI`. Three similar lines beat a premature helper.
- No comment narrates what code does. A comment explains a non-obvious why, or it does
  not exist.
- Fail fast. Swift: no silent `?? 0` on values the API guarantees. Decode with `Codable`
  and let a decoding error surface as a visible error state, never a blank screen.
  Python: no try/except in business logic. Catch at route boundaries and return a
  helpful error.
- Descriptive names. `plateAreaPx`, not `data`. `fighterAfterMeal`, not `result`.
- Every network call has a timeout. 10 s upload, 5 s everything else.
- SwiftUI views stay under 150 lines. Logic lives in the view model.
- No secrets or server URLs hardcoded in Swift. Read `API_BASE_URL` from `Config.xcconfig`.
- Build and run on a device after every meaningful change. Never write more than
  30 minutes of code without running it.
- Commit every 30 minutes with a message saying what was verified, for example
  `feat: capture view uploads JPEG and renders polygons (tested on iPhone 15)`.
- Record every non-obvious choice in `DECISIONS.md`, one line, what was chosen over what
  and why.

## Stack

| Layer | Choice |
|---|---|
| App | SwiftUI, iOS 17+, Swift 5.10, MVVM with `@Observable`, async/await |
| Networking | `URLSession`, `URLSessionWebSocketTask` |
| Camera | `AVCaptureSession` with photo output, `PhotosPicker` fallback |
| Dependencies | Auth0.swift via SPM. Nothing else. No CocoaPods. |
| Server | FastAPI, Python 3.11, uv |
| CV | Ultralytics YOLO segmentation, OpenCV for the scale reference |
| Vision fallback | IFM K2-Horizon, constrained label choice only |
| Game state | SQLite via SQLAlchemy |
| Player identity | MongoDB Atlas |
| Realtime | Redis Cloud pub/sub behind FastAPI WebSockets, HTTP polling fallback |
| Nutrition | USDA FoodData Central, `data/usda.sqlite`, no live API calls |
| Arena | One static HTML page, vanilla JS, served at `/arena/{code}` |

## Storage split

Three stores, each with one job. Do not blur them.

- **SQLite** holds everything on the hot path: meals, meal_items, fighters, fights,
  fight_turns, leagues. The photo path must return in under 4 seconds, so it never
  waits on a network database.
- **MongoDB Atlas** holds player identity and profile only: display name, emoji, Auth0
  subject, league membership, discoveries. Written on join and on profile change, never
  during a fight.
- **Redis Cloud** holds ephemeral realtime only: pub/sub channels per league and live
  fight state. 29 MB limit, so keys carry a TTL and nothing durable lives here.

## Layout

```
ios/project.yml        XcodeGen spec; `xcodegen generate` produces Mealee.xcodeproj
ios/Mealee/            SwiftUI app: API/, Models/, ViewModels/, Views/, Fixtures/
ios/MealeeTests/       BattleSimTests pins Swift to Python
server/app/            FastAPI, all CV code; server/tests/ pytest
arena/index.html       projector page
spikes/                standalone spike scripts and SPIKE_RESULTS.md
data/                  foods.yaml, nutrients_fallback.yaml, build_usda.py, usda.sqlite
```

Auth0 login is gated by `AUTH0_ENABLED` in `ios/Config.xcconfig`. Set it to `NO` at the
venue if login misbehaves; the app then goes straight to the join screen.

## Layers

- **Layer 0**, hour 4: app fully navigable on `MockAPI`, arena page on a fixture fight,
  server deployed with a health check. Demoable on its own.
- **Layer 1**, hour 9: real photo path end to end. Scan animation Tier A.
- **Layer 2**, hour 14: WebSockets, quick match between two phones, standings, seed data,
  nightly job, QR join. Scan animation Tier B.
- **Layer 3**, only if the above is green: vision fallback labels, carry-over stats,
  share image, Tier C.

Feature freeze at hour 18. After that, bug fixes on the demo path and polish only.

## Will not build

Accounts beyond Auth0 login, push notifications, real money, mixed-dish decomposition
(curry over rice is one item), settings screens, iPad layout, Android, App Store
submission, Core Data or SwiftData. App state is in memory plus a JSON cache in
Application Support.

## Done means

On two iPhones at the expo, a presenter photographs a judge's plate with a card on it,
sees outlines and grams within 4 seconds, sees stats with reasons, taps Quick match
against the second phone, and the fight plays on the projector arena with a readable
turn log. Three times in a row on venue wifi. And the app still demos end to end on
`MockAPI` if the wifi dies.
