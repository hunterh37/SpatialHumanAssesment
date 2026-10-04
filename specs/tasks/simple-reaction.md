# Simple reaction

Measures reaction time (RT) and movement time (MT).

## Flow

1. Familiarization: 5 trials, `familiarization: true`.
2. Scored: 20 trials.
3. Each trial: random foreperiod 0.8 to 2.0 s, then one blue sphere (radius 6 cm) spawns.
4. Trial ends on contact or after 3.0 s timeout (`miss`).

## Placement

Sample spawn points from reconstructed room surfaces and free space between 0.35 and 0.65 m from the shoulder, eccentricity 0 to 120 degrees. Balance trials across 4 eccentricity bins (0-30, 30-60, 60-90, 90-120). Without a room mesh use a shell around the head.

## Timing

- `move_t`: first hand sample after spawn where wrist speed exceeds 0.15 m/s for 50 ms. Threshold is a tunable constant.
- RT = `move_t - spawn_t`. MT = `contact_t - move_t`.
- Either hand counts. Log which in `hand`.

## Feedback

Pop sound and particle burst on contact. No score shown until the end.

## Done

20 scored trials logged with all fields. Median RT on a healthy adult falls between 0.25 and 0.6 s.
