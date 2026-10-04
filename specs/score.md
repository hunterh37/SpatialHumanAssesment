# Score

Code: `packages/ScoreKit`. Pure Swift, no UI or ARKit, shared by the app and the `scorekit` CLI.

```
Session JSON
  -> Signal      Stats (robust median, MAD trim, ex-Gaussian, OLS, Theil-Sen, d'), Kinematics
  -> Metrics     one extractor per game, MetricValue {value, n, sem}
  -> Norms       NormTable: expected(age) = mean25 + slope (a - 25) + accel max(0, a - 50)^2
  -> Age         SpatialAgeModel -> Spatial Age, interval, domains
  -> ScoreReport JSON for app, ingest, dashboard, showcase
PaceOfAging      across sessions
```

## Spatial Age

1. Each metric value inverts through its norm curve to a metric age, clamped 18 to 95.
2. Metric age SD = sqrt((sem / curve slope)^2 + tau^2). `tau` is the metric's residual error as an age predictor.
3. Metrics fuse into five domain ages (Speed, Decision, Control, Memory, Consistency) by inverse variance, variance inflated by 1 + (k - 1) 0.5.
4. Domains fuse the same way with rho 0.3, then combine with a prior N(chronological age, 9^2).

`evidence_age` is step 4 without the prior. `age_gap` = Spatial Age minus chronological.

Domain score 0 to 100 = mean percentile of its metrics against the age-25 reference.

## Pace of aging

Weighted least squares of Spatial Age on calendar years, at least 3 sessions over 28 days, shrunk toward 1.0 with prior SD 0.5. 1.0 is the calendar rate.

## Quality

Trials with tracking gaps over 100 ms drop (300 ms for pursuit, which masks missing samples). Flags: valid trial rate under 0.7, fewer than 3 games, catch rate under 0.5, omissions over 0.2.

## Norms

`NormTable.provisional` holds priors with sources. They are not fitted. Replace with values fitted on collected sessions (`age-model.md` v1) and bump `version`.

## CLI

```
make scorekit-test
make scorekit-synth     # 40 synthetic sessions -> data/synthetic-minigames
make scorekit-score     # ScoreReport JSON for them
```
