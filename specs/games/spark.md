# Spatial Tracking

Code: `Games/SparkGame.swift`. Metrics: `ScoreKit/Metrics/SparkMetrics.swift`. Task: `simple_rt`, see `specs/tasks/simple-reaction.md`.

Deck: sound and/or light says something is coming; the participant spots the incoming object and acts on it (punch, point) to make it disappear. 3D nature backdrop, branches or leaves falling with audio cues. Tests audio and visual to action reaction time and whether the participant can locate the cue.

## Flow

Forest clearing (`Scenery.forest`). 3 familiarization, 16 scored. Foreperiod 1.2 to 2.6 s.

1. Cue at a spot above the eyes (eye + 0.45 m) in a column 0.42 to 0.58 m from the dominant shoulder. Azimuth is balanced over 4 bins from 0 to 120 degrees, either side, so many cues start outside the field of view. Cue kinds `audio` (a spatial rustle from the spot), `light` (a soft flare at the spot, 0.5 s) and `both` are balanced and shuffled. Practice always uses `both`. `spawn_t` is cue onset.
2. 0.35 s later a gold leaf appears at the spot and drifts down at 0.38 m/s with a 5 cm side-to-side sway.
3. Touch: the nearest fingertip within 7 cm + 1 cm of the leaf center. The leaf pops with a praise cue. Reaching the ground is a miss.

Logged: `cue`, `eccentricity_deg` (angle from head forward to the cue spot at onset), `position` (leaf center at contact, the column for a miss), trace from 0.35 s before cue onset.

## Metrics

Onset comes from the fingertip trace (`Kinematics.onset`), with `move_t` as fallback. RT runs from cue onset, so it includes finding the cue.

`reach_rt`, `reach_mt` (robust medians), `rt_tau`, `rt_cv`, `ecc_slope` (reach time per 90 degrees: the cost of a cue away from where the participant faces), `peak_speed`, `path_efficiency`, `smoothness` (LDLJ).

## Open

- Metrics pool the three cue kinds. A per-cue split (audio vs light RT) needs norms first.
- RTs over 1.5 s drop as lapses (`ReactionTiming.maxRT`); a cue far behind can exceed that while the head turns.
