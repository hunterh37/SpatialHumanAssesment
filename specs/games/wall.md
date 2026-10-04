# Hole in the Wall

Code: `Games/WallGame.swift`. Metrics: `ScoreKit/Metrics/WallMetrics.swift`. Task: `wall`.

Deck: the participant stands on a platform surrounded by a moat. A wall with a cut-out comes at them and they hold that position. Tests mobility: how far the arms move to fit the shape, and whether a pose is consistently out of reach. Feet stay on the island. Nothing asks for a step, a lunge or a lean.

## Island

`Scenery.moat`: the forest clearing with a stone island (0.6 m radius, pale rim) under the participant and water out to 2.6 m. The wall starts beyond the water.

## Layout

Everything is placed in the participant frame: origin on the floor under the head when each block begins (after the countdown, once world tracking reports a tracked head), x right, y up, -z forward (`Rig`). The cutout centers are logged in world space.

- Wall: a box 1.6 m wide, at least 2.0 m and eye + 0.4 m tall, 2 cm thick, standing on the floor with its face toward the participant. Stone (`Theme.stone`) at 70 percent opacity. Taller only when needed to keep 25 cm of wall above the highest hole center.
- Cut-out: a standing human figure in ink on the face with a 12 mm pale rim (`BodySilhouette`): head, neck, trunk, legs and feet in proportions of stature H = eye / 0.936, and each arm solved as two bones (upper arm 0.186 H, forearm 0.146 H) from the shoulder joint to its hand hole, elbow bent down and outboard. A hand closer to the shoulder than the arm's length is drawn foreshortened (the arm also reaches toward the viewer); a strongly foreshortened arm, as in `forward`, shows an open palm, fingers up. Each hand is centered in its hole. The panel stays one plain mesh.
- Holes: two blue (`Theme.go`) rings of 10 cm radius and 1 cm tube at the ends of the arms.
- Motion: the wall starts 3.0 m ahead (z = -3.0) and moves at constant speed to z = -0.30 over 5.0 s, about 0.54 m/s. The hand targets sit in the wall plane, so they arrive at z = -0.30 too. For the `forward` pose they stop at z = -0.55, still after 5.0 s, so the wall is a little slower (about 0.49 m/s) and the hold window is the same length.

With eye height `e` and shoulder height `sh = e - 0.25` (the estimate `GameContext.shoulder` uses), the six poses place the cutout centers at these rig-local (x, y), in meters:

| Pose | Left | Right |
|---|---|---|
| `arms_out` | -0.55, sh | 0.55, sh |
| `arms_up` | -0.20, e + 0.30 | 0.20, e + 0.30 |
| `reach_left` | -0.65, sh + 0.05 | -0.25, sh + 0.05 |
| `reach_right` | 0.25, sh + 0.05 | 0.65, sh + 0.05 |
| `high_low` | -0.35, e + 0.20 | 0.40, sh - 0.35 |
| `forward` | -0.15, sh | 0.15, sh |

Left and Right name the hand, not the side of the wall. In `reach_left` both holes sit left of center and the right hand reaches across to the inner one. Each hand is scored against its own hole.

## Flow

1 familiarization wall (`arms_out`), 8 scored. Scored walls take the six poses in one shuffle drawn from the block seed and cycle through it, so every pose appears before any repeats and the order replays from the seed.

Per wall:

1. The wall appears at 3.0 m and hangs still for 0.6 s, rings breathing, so the pose can be read. This pause is not logged.
2. `start_t` is the first frame of motion. The rings keep breathing while the wall approaches.
3. At `hold_start_t = start_t + 3.5` the rings go still. That is the only cue. There is no tone, so nothing startles the head into moving.
4. At `pass_t = start_t + 5.0` the wall has arrived. The outcome is decided and the feedback plays for about 0.45 s.
5. The wall is removed and the game waits 1.0 s before the next one.

Each ring glows with the distance from its own hand to where its hole will stop, so the hand finds the spot early, and the glow never says when to move. The HUD shows the title, the instruction from `Game.instruction` and progress dots. No numbers during play.

Feedback:

- Cleared: both rings pop with a paper ring (`Micro.pop`) and the wall fades.
- Hit: the wall flashes `Theme.nogo`, sinks 3 cm and fades with the quiet low tone, and the rings take the miss sink.

## Hold window

From `hold_start_t` to `pass_t`, 1.5 s, every frame logs the head position and each tracked hand point. The hand point is the midpoint of the wrist and the index fingertip. A hand sample counts once, by its tracker timestamp, and only inside the window.

Logged per wall:

- `pose`, `start_t`, `hold_start_t`, `pass_t`.
- `left_target`, `right_target`: where the hole centers stop, world space. Hands are scored against these fixed points, not the moving holes, so the wall's own approach never counts as error.
- `left_error_m`, `right_error_m`: mean distance from that hand point to its target over the hold. Null if the hand was never tracked.
- `head_sway_cm_s`: head 3D path length over the hold divided by the sampled hold duration, times 100.
- `hand_drift_cm`: for each hand with at least two samples, the RMS distance of its points from their own mean, times 100, averaged over those hands. Null if neither qualifies.
- `outcome`: `cleared` when both hands have samples in the last 0.5 s before `pass_t` and each averages within 12 cm of its target over them. Otherwise `hit`, including a hand that was not tracked then. The constants are `WallMetrics.clearRadiusM` and `WallMetrics.clearWindowS`.
- `tracking_gap_ms`: the larger of the left and right hand's longest gap from `hold_start_t` to `pass_t`, so a trial needs both hands tracked.

## Metrics

- `wall_worst_pose_cm`: mean hand error per pose (both hands), the worst pose, cm, from 2 poses up. Display only; it flags a pose the participant cannot reach.

Scored blocks only. Trials with a tracking gap over 100 ms drop. A metric with no data is omitted.

- `wall_sway_cms`: robust median of `head_sway_cm_s` over kept walls, cleared or hit. The game headline, and in the age model (Control domain, v0.3 norms).
- `wall_hand_drift_cm`: robust median of `hand_drift_cm` over kept walls that have one. In the age model (Control domain).
- `wall_clear_rate`: cleared walls over kept walls. Display only. `sem` from `GateMetrics.binomialSE`.

Both age-model norms are placeholders: no head-sway reference exists for a headset, so they need calibration on collected sessions.

## Open

- Head sway is raw path length of the device pose, so tracking noise sets a floor and turning the head moves the device a few cm. Calibrate the floor on a still participant before reading small differences.
- The wall stops 0.30 m ahead of the head, so at arrival the translucent panel covers the whole field of view. Check on device that this reads as the wall arriving and not as a dimmed room.
- The 12 cm clear radius is a first guess. The hand point is not the palm center, so hand size shifts the error.
