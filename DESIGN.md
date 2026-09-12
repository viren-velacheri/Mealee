# Mealee design

Palette from coolors.co/f7fff6-bcebcb-87d68d-93b48b-8491a3. Mist is the ground, mint is
glass tint, leaf is the one accent, sage is secondary emphasis, slate is quiet text. One
deep tone, ink `#1E2A22`, is derived from sage for readable text; the swatches have none.

## Feel

Light, quiet, mint glass. Every surface is a frosted card on a slowly drifting aurora.
Type is SF Rounded for anything that carries weight (numbers, names, titles) and plain
SF for body. Corners are 28 pt continuous. Nothing is pure white, nothing is pure black.

Motion has one vocabulary: springs. `Motion.bounce` for things that land, `settle` for
things that grow, `snappy` for presses. Screens and cards leave as a ripple through glass
(`.liquid`), never a cut. Every tap is a light impact, every hit is rigid, every win is a
success tap.

## Shaders (`Design/Shaders.metal`)

| Shader | Where |
|---|---|
| `aurora` | App background on every screen and the projector |
| `shimmer` | Stat meters and HP bars, so they read as liquid |
| `dissolve` | The plate photo being eaten in the scan sequence |
| `ripple` | The liquid transition between states |

## Components

- `glassCard(tint:)` frosted material with a mint tint, hairline highlight, sage shadow.
- `primaryPill(filled:)` the one call to action per screen, leaf gradient.
- `Pressable` scales to 0.95 with a light haptic.
- `StatMeter` / `StatMeters` / `HPBar` liquid bars with shimmer and numeric transitions.
- `StreamingText` reveals a line a character at a time with a glowing head.
- `PopNumber` a damage or stat number landing with a bounce and a leaf glow.
- `AuroraBackground`, `WinnerBurst`, `Shake`, `Pill`.

## Flows and what each screen shows

**Home.** The fighter first: sprite, name, three pills (HP, wins this week, first strike).
Six meters. Reasons hidden behind "Why" so the screen stays calm; they stream in when
asked. Two intake chips. One filled action (Log a meal), one quiet (Fight).

**Capture.** Full-bleed camera, a dashed mint frame for the card, a big white shutter
that rings out on press. Uploading is a glass pill with a shimmering bar, not a spinner.

**Scan.** The photo is scanned by a leaf line, each food outline draws itself with a
light tap, cutouts lift with a spring, the background is eaten by the `dissolve` shader,
labels arrive as glass chips. Tap anywhere to skip. Under 1.2 s.

**Review.** Each item: emoji, name (tap to change on a grid sheet), "≈ 55 g" large with the
range small. Confidence and scale live behind a "Details" disclosure. Confirm is the only
filled button.

**Stat delta.** Meters spring from before to after; each reason streams in. Done.

**Fight.** Pick a rival from horizontal glass cards; swipe the selected card up into the
ring or press Fight. Playback: two cards with liquid HP, hits shake the target and pop a
damage number, the log streams line by line, the winner gets a burst of palette dots.
"Verify replay" proves the phone can reproduce the fight from the seed.

**League.** Code as the hero, QR under it, standings as glass rows with rank badges,
tonight's card, Foodex counts.

**Foodex.** A 5-wide grid of glass tiles; discovered tiles flip in.

## Rules

- One accent per screen. Leaf marks the action, never decoration.
- Numbers use `.contentTransition(.numericText())`; they never jump.
- Reduced motion: streaming shows whole lines, the scan fades, bursts are skipped.
- Views stay under 150 lines; components live in `*Components.swift` and `Design/`.
