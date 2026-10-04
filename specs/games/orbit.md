# Orbit

Code: `Games/OrbitGame.swift`. Metrics: `ScoreKit/Metrics/OrbitMetrics.swift`. Task: `pursuit`.

A teal orb (4 cm) waits at the path start, breathing, until a fingertip rests inside it for 0.5 s (10 s cap). Then it moves on a 3D Lissajous path centered 0.2 m below eye level and 0.45 m ahead: amplitudes 0.20, 0.12, 0.08 m, frequencies 0.21, 0.29, 0.13 Hz, random phases. Six fading dots show the next 0.3 s of path.

1 familiarization (6 s), 3 scored (12 s). Samples at 30 Hz in the participant frame (origin under the head at game start, -z forward) so the logged path reproduces the target.

## Metrics

First second unscored. `pursuit_rms_cm`, `pursuit_lag_ms` (shift of the analytic path that best fits the fingertip, 0 to 500 ms in 5 ms steps), `pursuit_on_target` (inside 4 cm), `pursuit_gain` (velocity projection, so tremor does not inflate it).
