# Pendulum

Code: `Games/PendulumGame.swift`. Metrics: `ScoreKit/Metrics/PendulumMetrics.swift`.

A gold bob (8 cm) hangs on a cord from a pivot 0.4 m above eye level and 0.48 m ahead. It swings in the frontal plane at 22 to 34 degrees, cord length 0.55 to 0.85 m. After 1.5 to 4.0 s, picked at random, the cord releases and the bob falls ballistically from its release state at 9.81 m/s^2. The participant pinches it out of the air.

Swing and fall are analytic (`theta = A cos(w t)`, then `p0 + v0 t - g t^2 / 2`), so the logged release state is the exact start of the trajectory shown.

## Catch

Grasp point (midpoint of thumb and index tips) within 7 cm of the bob center with aperture under 4.5 cm. Catch time is the hand sample time. Under 100 ms after release is `anticipation`. A fall past 1 m or to the floor is `drop`.

A life-size cm ruler stands behind the swing plane, zero at the top. On a catch a gold tick and the drop in cm mark the height.

## Flow

3 familiarization trials, 12 scored.

## Metrics

`catch_latency` (median, s), `catch_drop_cm` (median vertical fall, display, the ruler drop equivalent d = g t^2 / 2), `catch_rate`.
