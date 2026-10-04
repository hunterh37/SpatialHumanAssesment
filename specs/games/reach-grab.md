# Reach and Grab

Code: `Games/ReachGrabGame.swift`. Metrics: `ScoreKit/Metrics/ReachGrabMetrics.swift`. Task: `reach_grab`.

How far a participant can reach, and lean, with feet planted. Gold cubes (6 cm, rounded) hang at shoulder height at set distances from the dominant shoulder, and the participant touches each with a fingertip. The distances climb past arm's length, so the last cubes are won by leaning.

## Layout

Two ladders of six cubes, elevation 0, distances from the dominant shoulder of 0.50, 0.58, 0.66, 0.74, 0.82 and 0.90 m.

| Ladder | Direction from the shoulder |
|---|---|
| forward | azimuth 0, straight ahead |
| side | 45 degrees toward the dominant side |

Placement is `GameContext.reachPoint`, so the shoulder is the same estimate Spark and Gate use. A left-handed participant gets the side ladder on the left (reachPoint azimuth -45). The log stores `azimuth_deg` toward the dominant side, so the side ladder is +45 for both hands. `ambi` is treated as right, as `GameContext` does. Each cube is turned square to the line from the shoulder.

## Flow

2 familiarization, up to 12 scored.

Familiarization: two cubes straight ahead at 0.45 and 0.55 m. Both always show.

Scored: one cube at a time, the ladders interleaved, forward first, nearest first: forward 0.50, side 0.50, forward 0.58, and so on. A miss ends its ladder, because the next rung is farther, and the rest of that ladder is skipped. Progress dots still advance for skipped cubes. The block ends when both ladders are done or after `trials` cubes. 0.6 s pause between cubes.

The HUD shows the instruction from `Game.instruction`, the title and progress dots. No numbers during play.

## Grab

The nearest fingertip of either hand within 3 cm (half the edge) plus 1 cm (`ReachTrial.contactSlack`) of the cube center. 6 s without a grab is a miss.

Micro-interactions: appear, breathe, proximity glow, pop with ring on a grab (paper ring), sink on a miss. The pop pitch climbs one step per rung, so the ladder is audible. Speed is not rewarded here, so reach time does not set the pitch.

Logged per cube:

- `spawn_t`: first frame the cube is in the scene.
- `grab_t`: hand sample time of the grab, null for a miss. `hand`: the grabbing hand, null for a miss.
- `distance_m`: ladder distance, shoulder to cube center. `position`: cube center in world space.
- `lean_m`: horizontal distance between the head at the grab and the rig origin, which is under the head when the game began. Null for a miss.
- `tracking_gap_ms`: longest gap of the grabbing hand from spawn to grab. For a miss, the best of either hand over the 6 s.
- `trace`: fingertip path from 0.35 s before spawn to the grab, null for a miss.

## Metrics

Scored blocks only. Trials with a tracking gap over 100 ms drop. A metric with no data is omitted.

- `reach_max_cm`: furthest kept grab, ladder distance in cm. Depends on arm length, so it is display only. `sem` is null.
- `reach_lean_cm`: largest lean over kept grabs, cm. The game headline and the only one of the three in the age model (Control domain, v0.3 norms). `sem` is null.
- `reach_grab_rate`: kept grabs over kept trials. `sem` from `GateMetrics.binomialSE`.

## Open

- Lean is head travel, and the norm source (functional reach) measures hand reach. Calibrate on collected sessions.
- The rig is anchored once per game by the Director, before practice. A participant who shifts their feet between practice and the scored block adds to lean. Re-anchoring at the start of the scored block would fix the start pose.
- The gap window starts at spawn, so a hand that starts out of view counts the time before it enters view. Spark and Gate share this rule.
