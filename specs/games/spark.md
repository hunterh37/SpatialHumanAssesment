# Spark

Code: `Games/SparkGame.swift`, `Games/ReachTrial.swift`. Metrics: `ScoreKit/Metrics/SparkMetrics.swift`. Task: `simple_rt`, see `specs/tasks/simple-reaction.md`.

One blue sphere (6 cm radius) after a 0.8 to 2.0 s foreperiod, 0.35 to 0.65 m from the dominant shoulder, eccentricity balanced over 4 bins from 0 to 120 degrees, elevation -15 to 20 degrees. Contact: fingertip within radius + 1 cm. Timeout 3 s.

5 familiarization, 20 scored.

## Metrics

Onset comes from the fingertip trace (`Kinematics.onset`), with `move_t` as fallback.

`reach_rt`, `reach_mt` (robust medians), `rt_tau` (ex-Gaussian tail), `rt_cv`, `ecc_slope` (reach time per 90 degrees), `peak_speed`, `path_efficiency`, `smoothness` (LDLJ).
