# Gate

Code: `Games/GateGame.swift`. Metrics: `ScoreKit/Metrics/GateMetrics.swift`. Task: `choice_rt`, see `specs/tasks/choice-reaction.md`.

Go trials show blue and orange at least 25 cm apart. No-go trials show orange alone. Exactly 70 percent go, shuffled. Window 2 s. Placement as Spark.

5 familiarization, 30 scored.

## Metrics

`choice_rt`, `decision_time` (choice RT minus Spark RT, computed in `ScoreEngine`), `commission_rate`, `omission_rate`, `d_prime` (log-linear corrected).
