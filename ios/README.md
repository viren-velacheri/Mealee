# Mealee iOS

## First build (Friday night, do not leave this for Saturday)

1. Xcode 16 or newer (Auth0.swift 2.22+ needs it), then `brew install xcodegen`
2. `cd ios && cp Config.example.xcconfig Config.xcconfig` and set `API_BASE_URL` to the
   server (LAN IP on venue wifi, or the Railway URL). Leave `DEVELOPMENT_TEAM` blank for
   a Personal Team, or paste the 10-character Team ID from developer.apple.com.
3. `cp Mealee/Resources/Auth0.plist.example Mealee/Resources/Auth0.plist` (already the
   right values; the real file is gitignored so it can be swapped without a commit).
   The SDK reads only `ClientId` and `Domain`. `CallbackMode` is a Mealee key read by
   `Auth0Session.swift` to decide between the custom scheme and Universal Links.
4. `xcodegen generate` then `open Mealee.xcodeproj`.
5. Signing & Capabilities: tick "Automatically manage signing", pick the team. Personal
   Team installs expire in 7 days, which covers the hackathon.
6. Plug in every demo iPhone, select it, Run. Grant camera permission on first launch.

## Auth0 dashboard, needed before login works

Application `bSRJI0KnQw0wEPTGDvRpibzpg7RCLY0Y` on `dev-c2da7fus6cmejyml.us.auth0.com`.
Paste these exact strings, the bundle id is part of them:

- Allowed Callback URLs:
  `edu.cmu.hackcmu.mealee://dev-c2da7fus6cmejyml.us.auth0.com/ios/edu.cmu.hackcmu.mealee/callback`
- Allowed Logout URLs: the same string.
- iOS App Bundle Identifier: `edu.cmu.hackcmu.mealee`
- Apple Team ID: only if you have a paid account and want Universal Links (iOS 17.4+).
  Not needed for the custom scheme, which is what `CallbackMode` selects.

If Auth0 misbehaves at the venue set `AUTH0_ENABLED = NO` in `Config.xcconfig` and
rebuild. The app then skips the login screen entirely.

## Offline demo

Set `API_BASE_URL` to `mock` in `Config.xcconfig`. Every screen runs on bundled
fixtures and fights are simulated on the phone. This is the fallback if wifi dies.

## Tests

`MealeeTests/BattleSimTests.swift` pins the Swift fight simulation to the Python one.
Run with Cmd+U. If it fails after a change to `server/app/battle.py`, regenerate the
fixture with `python3 spikes/spike_battle.py`.

## Design

`DESIGN.md` at the repo root is the system: palette, type, motion, shaders, and what each
screen shows. `Mealee/Design/Shaders.metal` compiles with Xcode's default Metal toolchain;
nothing to install. If a shader misbehaves on a device, every use is a single modifier
(`.colorEffect` or `.distortionEffect`) that can be commented out without touching layout.
