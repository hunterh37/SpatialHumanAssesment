# Scary Balance

Code: `Games/ReachGrabGame.swift`. Metrics: `ScoreKit/Metrics/ReachGrabMetrics.swift`. Task: `reach_grab` (name kept from the earlier Reach and Grab game).

Deck: items are spread across the room; the participant goes over to pick each one up. At random or preselected points a "monster" comes by and the participant must hold their position until it passes. Need not be scary. Tests reach and lean (how far they can reach) and holding a position and shaking.

## Walk

Six floor spots in the start frame, x right and z forward negative: (0, -0.6), (0.6, -0.3), (-0.6, -0.3), (0.45, 0.45), (-0.45, 0.45), (0, 0), all within 0.8 m so the walk stays inside the immersive boundary. Each trial shows a gold ring on the floor at the next spot. HUD: "Walk to the glowing spot." The trial goes on once the head is within 25 cm of the spot, or after 12 s. After a 0.4 s settle the game anchors a frame at the head, facing away from the start (the center spot faces the start direction). The cube and lean are measured in that frame. `stand_at` logs it.

## Freeze

About one scored trial in three (seeded), and the second practice cube, a purple creature drifts across 2.3 m ahead, from left to right over 3.0 s, humming. HUD cue "Freeze!". It starts 0.7 to 1.3 s after the cube appears, mid-reach. The cube is not touchable while it passes, and the 6 s window pauses. Then "Go!" and the reach goes on.

Logged in `freeze`: `start_t`, `end_t`, `head_sway_cm_s` (head path over duration), `hand_drift_cm` (RMS of the fingertip of the hand nearest the cube about its mean), `head_shift_cm` (largest head travel from the freeze start), `held` (shift at most 8 cm, `ReachGrabMetrics.freezeBreakCm`), `tracking_gap_ms` of that hand.

## Layout

Two ladders of six cubes, elevation 0, distances from the dominant shoulder of 0.50, 0.58, 0.66, 0.74, 0.82 and 0.90 m.

| Ladder | Direction from the shoulder |
|---|---|
| forward | azimuth 0, straight ahead |
| side | 45 degrees toward the dominant side |

Placement uses the shoulder estimate `GameContext.shoulder` uses (18 cm to the side, 25 cm below the eyes), in the frame anchored at the spot. A left-handed participant gets the side ladder on the left (reachPoint azimuth -45). The log stores `azimuth_deg` toward the dominant side, so the side ladder is +45 for both hands. `ambi` is treated as right, as `GameContext` does. Each cube is turned square to the line from the shoulder.

## Flow

2 familiarization, up to 12 scored.

Familiarization: two cubes straight ahead at 0.45 and 0.55 m from the first spot. Both always show.

Scored: one cube at a time, each at the next floor spot, the ladders interleaved, forward first, nearest first: forward 0.50, side 0.50, forward 0.58, and so on. A miss ends its ladder, because the next rung is farther, and the rest of that ladder is skipped. Progress dots still advance for skipped cubes. The block ends when both ladders are done or after `trials` cubes. 0.6 s pause between cubes.

The HUD shows the instruction from `Game.instruction`, the title and progress dots. No numbers during play.

## Grab

The nearest fingertip of either hand within 3 cm (half the edge) plus 1 cm (`ReachTrial.contactSlack`) of the cube center. 6 s without a grab is a miss.

Micro-interactions: appear, breathe, proximity glow, pop with ring on a grab (paper ring), sink on a miss. The pop pitch climbs one step per rung, so the ladder is audible. Speed is not rewarded here, so reach time does not set the pitch. Reaching the floor spot plays `.lock`; a held freeze plays `.soft` from the cube, a broken one `.wrong`.

Logged per cube:

- `spawn_t`: first frame the cube is in the scene.
- `grab_t`: hand sample time of the grab, null for a miss. `hand`: the grabbing hand, null for a miss.
- `distance_m`: ladder distance, shoulder to cube center. `position`: cube center in world space.
- `lean_m`: horizontal distance between the head at the grab and where the head was when the cube appeared. Null for a miss.
- `tracking_gap_ms`: longest gap of the grabbing hand from spawn to grab. For a miss, the best of either hand over the 6 s.
- `trace`: fingertip path from 0.35 s before spawn to the grab, null for a miss.

## Metrics

Scored blocks only. Trials with a tracking gap over 100 ms drop. A metric with no data is omitted.

- `reach_max_cm`: furthest kept grab, ladder distance in cm. Depends on arm length, so it is display only. `sem` is null.
- `reach_lean_cm`: largest lean over kept grabs, cm. The game headline and the only one of the three in the age model (Control domain, v0.3 norms). `sem` is null.
- `reach_grab_rate`: kept grabs over kept trials. `sem` from `GateMetrics.binomialSE`.
- `freeze_sway_cms`, `freeze_hand_drift_cm`: robust medians over freezes with a gap of 100 ms or less, whatever the reach outcome. Control domain, placeholder priors.
- `freeze_held_rate`: held freezes over kept freezes. Display only.

## Open

- Lean is head travel, and the norm source (functional reach) measures hand reach. Calibrate on collected sessions.
- A participant who steps toward the cube after it appears adds to lean; nothing checks the feet.
- The gap window starts at spawn, so a hand that starts out of view counts the time before it enters view. Spark and Gate share this rule.
