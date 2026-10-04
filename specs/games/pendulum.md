# Stick Drop

Code: `Games/PendulumGame.swift`. Metrics: `ScoreKit/Metrics/PendulumMetrics.swift`. Task: `pendulum` (name kept from the earlier pendulum game).

Deck: a set of objects hangs in view, a random one falls, and the participant grabs it before it hits the ground. Nature backdrop. Leaves fall at different speeds, faster over time. Tests visual to action reaction time and useful field of view.

## Layout

Forest clearing (`Scenery.forest`). A bark branch runs in an arc in front of the participant. Seven gold leaves (11 cm) hang from it at azimuth -60, -40, -20, 0, 20, 40, 60 degrees from the start direction, 0.52 m from the head horizontally, stems 12 cm above the eyes. The azimuths are fixed so every session tests the same field.

## Flow

3 familiarization, 16 scored. Each trial waits 1.0 to 3.0 s, then one leaf lets go with a tock. Leaves fall in shuffled passes over the row, so each position falls equally often.

The fall is analytic, `p0 - g s tau^2 / 2`, from rest. Gravity scale `s` ramps linearly from 0.25 to 1.0 across the scored block; practice stays at 0.25. The leaf turns slowly as it falls (visual only). A fresh leaf grows back on the stem after each trial.

## Catch

Any hand joint or bone segment (wrist to fingertips, knuckle span) within 6.5 cm of the leaf center. No pinch required; aperture is still logged. Catch time is the hand sample time. Under 100 ms after release is `anticipation`. Reaching the ground is `drop`. A catch plays the caught tone, a gold ring and a praise cue; the leaf rides in the hand for 0.45 s.

Logged per trial: `release_t` (first falling frame), `release_position` (leaf center), `release_velocity` zero, `release_angle_deg` and `stick_index` (which leaf), `eccentricity_deg` (angle from head forward at release), `gravity_scale`. `length_m` and `amplitude_deg` are 0.

## Metrics

`catch_latency` (median, s), `catch_drop_cm` (display, the 1 g ruler drop equivalent of each latency, d = g t^2 / 2, so the gravity ramp does not change it), `catch_rate`, `catch_ecc_slope` (catch latency per 90 degrees of eccentricity, the field of view cost, from 6 catches up).
