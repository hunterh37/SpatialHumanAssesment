# Dusk theme applied

Spec: `concept/SpatialAge_Dusk_Design_Spec.pdf` v1.0. Build: `xcodebuild` visionOS Simulator, BUILD SUCCEEDED. Window and immersive stage checked in the simulator (consent screen, Gate and Pendulum HUD).

## Changed

- `Design/Theme.swift`: `Dusk` enum with the spec's tokens verbatim, plus `line`, `glassHighlight`, `gaze`, `shadow`, `leaf`, layout (60 pt hit, 16 pt spacing, 46 pt radius) and motion springs (0.3 s, bounce 0.15). `Color.dusk*` mirrors. `Look.veil` for translucent unlit. Ink sky tokens removed; scenery tokens remapped to Dusk. Signal colors untouched.
- `Design/DuskStyle.swift` (new): glass modifier (charcoal 0.52 over system glass, 1 px edge, 1 px top highlight), primary / secondary / tertiary / icon button styles (gaze 1.035 plus halo or chipStrong, pinch 0.95, disabled 35%), toggle, segmented control, chips, 6 pt bars (XP accent to accentStrong), progress dots, type roles.
- `Stage/Stage.swift`: Dusk valley replaces the ink dome and floor grid. Gradient sky (150 solid latitude bands), sun and halo at azimuth 100°, elevation 5°, 9 clouds at 45%, far mountains plus haze, near mountains, hills, lake with static ripples, grass island, two-tone tree silhouettes from 6.2 m out. Clouds drift only while `hud.ambient` is true and Reduce Motion is off.
- `Design/Meshes.swift`: `skyBand`, `ridge`, `ellipse`. Band meshes are double-sided; one-sided inward winding was culled in the simulator.
- `Design/Scenery.swift`: forest adds nothing near the targets; the stage supplies trees. Moat water uses `Dusk.lake`.
- `App/ContentView.swift`, `Catalog/*`: plain window style with Dusk glass. Consent, participant, then a system `TabView` (leading ornament: Home, Games, Progress, Duel). Home, Games (4 x 2 grid of all eight games, "Play all"), game intro (practice toggle, "Before you start", "Skip this game"), Results, Progress (Swift Charts trend with 80% band in accentSoft, dashed chronological age, domain chips), Duel, all per section 7. Anatomy and Sky Plank controls moved from the window top into a Home side card.
- `Catalog/DuskCopy.swift` (new): game card copy from section 7, exact. ScoreKit `title` / `instruction` stay unchanged for reports and stored sessions.
- HUD (`Stage/ImmersiveView.swift`): strong-glass capsule at the top (0.42 m above eye at 1.4 m) with label, instruction, progress dots (done 75% ink, current gold, upcoming chipStrong) and a two-tap skip (×). Countdown and praise in glassInk; blue cue color removed. Queue counter "2 / 5" removed (no numbers during play).
- `Stage/Director.swift`: each game runs in its own task so skip ends only that game; a skipped block records nothing. Practice block is skipped when the toggle is off. Ambient motion frozen while blocks run.
- `App/AppModel.swift`: tab, intro, `practiceFirst`, local two-player `Duel` (4 rounds: Pendulum, Spark, Gate, Color Dots; higher ScoreKit game score wins the round), `history()`. A session where every game was skipped is not scored.
- Copy: exclamation marks removed from praise and cues. "Spatial Age" in UI replaced with "movement age".
- `Design/MicroInteractions.swift`: breathe is off under Reduce Motion (spec section 8).
- `apps/dashboard/index.html`: Dusk CSS tokens, Urbanist / Figtree / JetBrains Mono, LIVE dot, player boards with hero "Last catch" ms, 16-point sparkline on a fixed 250 to 750 ms scale with 300/500/700 grid, median and caught count, rounds dots, leaderboard from `GET /sessions` with current players in accentSoft, tiles for sessions, age range, valid-trial rate.

## Conflicts and gaps

- Game card copy describes mechanics that differ from the current games (Pendulum: "weight when the cord lets go", the game drops a leaf; Spark: "touch each light", the game drops leaves after a sound/light cue). Copy was applied exactly as the spec requires; either the copy or the games need a decision.
- The spec lists eight games; `Game.catalog` in ScoreKit lists five. The Games tab and "Play all" use all eight via `Game.dusk`; ScoreKit was not changed.
- HUD moved from 0.5 m below eye to 0.42 m above eye per section 7 ("at the top"). `specs/games/design.md` placed it low to keep the eye-level band clear; the new position is above the Pendulum leaf row (about 13° up) but may sit behind high Spark leaf columns.
- Duel runs as turn-taking on one headset. Two-headset sync does not exist in the codebase.
- Not built: music ("Golden Hour" Suno loop, and the Home mini-player), ambient leaves (menus never show the immersive scene), clinic view. No audio asset exists in the repo.
- Progress XP is derived (10 XP per scored game, level every 100 XP); no XP system existed. Domain "improved" requires the domain age drop to exceed 1.645 x the combined SD of the two estimates (SD defaults to 5 years when missing).
- Dashboard: live events carry no participant code or round, so boards key on `participant` / `code` when present and fall back to one "Player" board; "Round N of 4" shows only if events include `round`.
- Session schema untouched; no version bump needed.
