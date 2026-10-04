# Constellation

Code: `Games/ConstellationGame.swift`. Metrics: `ScoreKit/Metrics/ConstellationMetrics.swift`. Task: `corsi`, see `specs/tasks/corsi-3d.md`.

Nine stars (4 cm radius) placed across 140 degrees of azimuth, 0.45 to 0.62 m out, at least 18 cm apart, fixed for the game. Full immersion has no room surfaces, so stars float in reach instead of sitting on planes.

A sequence lights gold, 0.8 s on, 0.2 s gap, each star with its own note. Then all stars breathe and the participant touches them back in order. A touched star flashes white. A star re-arms once the fingertip leaves 8 cm. The trial ends on the first wrong star, on a full response, or after 8 s plus span.

Staircase from span 2: two attempts per span, two failures stop, cap span 9, 14 trials or 4 minutes.

## Metrics

`corsi_span`, `corsi_total` (span x correct sequences), `corsi_tap_interval`.
