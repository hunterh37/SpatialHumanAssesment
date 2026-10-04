# Age model

## v0, literature prior (works with zero data)

Each feature becomes a z-score against a reference mean and SD for age 25 (`ml/sha_biomarkers/norms.py`). Functional age = 25 + weighted sum of signed z-scores times years per SD. Constants are placeholders until replaced with values from published norms. Every constant cites its source in a comment.

## v0.2, Klemera-Doubal

`ml/sha_biomarkers/kdm.py`. Input is a matrix: rows are people, columns are biomarkers named by ScoreKit metric ids. Output is one age per row with a standard error.

Each biomarker follows `x(a) = mean25 + slope (a - 25) + accel max(0, a - knee)^2` with residual SD `sd` given age. The age minimizes `sum ((x_j - x_j(a)) / sd_j)^2`, plus `((a - CA) / 9)^2` when chronological age is given (BA_EC). With linear curves this is the closed-form KDM estimate; with a knee it is solved by Gauss-Newton on the curves' tangents. Weight comes from `slope / sd`, so a flat or noisy biomarker carries little evidence. Missing values are skipped per row.

KDM needs each biomarker's curve and residual SD from a reference sample. Until sessions are collected, `kdm_params.json` holds literature priors with a source per entry. Shapes come from the studies; levels are provisional for the headset. `fit` estimates linear parameters from collected sessions. Biomarkers must be conditionally independent given age, so the config keeps one metric per construct.

| Biomarker | Game | Shape source |
|---|---|---|
| `catch_latency` | Pendulum | Der and Deary 2006 |
| `reach_rt` | Spark | Der and Deary 2006, Dykiert 2012 |
| `rt_tau` | Spark | Hultsch 2002, West 2002 |
| `choice_rt` | Gate | Der and Deary 2006, Comms Med 2025 |
| `omission_rate` | Gate | Comms Med 2025 |
| `corsi_span` | Constellation | Facchin 2024 |
| `pursuit_rms_cm` | Orbit | direction only, placeholder magnitude |

### Pipeline

Raw sessions are the record; metrics are recomputed from them, so an extractor fix reaches every past session.

```
data/sessions/*.json     ingest saves every uploaded session (schema 0.5)
  -> make kdm-matrix     scorekit matrix: data/kdm/matrix.csv, one row per session
  -> make kdm            python -m sha_biomarkers.kdm: data/kdm/ages.csv
```

`matrix.csv` columns: `session_id`, `code`, `started_at`, `age`, `sex`, `handedness`, `height_cm`, `weight_kg`, `posture`, `mode`, `prior_sessions`, `calibration`, `usable`, `device_id`, `device_model`, `app_version`, `schema_version`, then one column per ScoreKit metric id. Empty means the session did not produce that metric.

`calibration` is 1 for the first usable Play-all session of each participant code. Fit norms and validate on those rows only (`--calibration-only`): repeat plays carry practice, duels and single games are partial.

`ages.csv` gives `kdm_age` (biomarkers only, BA_E) and `kdm_age_prior` (with the chronological prior, BA_EC), each with a standard error. Validate `kdm_age` against `age`; the prior version contains the answer.

### Partial sessions

A row needs one biomarker. Missing games are skipped and widen the standard error; with one or two games `kdm_age` is weak and `kdm_age_prior` stays near chronological age.

### Learning from sessions

`make kdm-fit` (`ml/sha_biomarkers/kdm_fit.py`) refits the parameters on every collected session.

- Every refit starts from the literature priors in `kdm_params.json` and adds all eligible people, so no session is counted twice.
- Per biomarker, `mean25` and `slope` get a robust Bayesian linear regression with the literature value as prior. Huber weights (threshold 1.5 residual SD) let a person far off the curve, such as a mistyped age or a distracted run, count less; the report counts them as `outliers`. Prior widths: baseline prior SD is one between-person SD, slope prior SD half the literature slope. `sd` is pooled with the literature `sd` as 10 pseudo-observations. Knee and curvature stay from the literature. Under 3 people a biomarker keeps its prior.
- Time metrics (`unit` s) scale their slope and curvature priors with the fitted baseline, after proportional slowing (Brinley).
- Fitting uses the first session per participant code that produced the biomarker, so single-game and duel sessions count. Validation uses calibration rows only.
- Leave-one-out: each validation person is predicted from parameters fitted without their sessions. The report gives MAE for the candidate, the current parameters and predict-the-mean, Pearson r, and the linear bias correction of the age gap fitted on the held-out predictions.
- A candidate is adopted into `data/kdm/params.json` only with 5 or more validation people and MAE no worse than the current parameters (`--force` overrides). Every candidate and report is kept in `data/kdm/history/`, named `fit-<date>-<time>-n<people>`.
- The report also lists validation people per age decade and the mean standardized residual per `device_id`. Do not pool headsets whose offsets differ.
- `make kdm` uses `data/kdm/params.json` when it exists and adds `kdm_gap_corrected`.

Fitted parameters stay under `data/` with the sessions. The app's Spatial Age still uses `NormTable.provisional` (`prior-0.4`, same shapes as `kdm_params.json` for the shared metrics); it does not read fitted parameters yet.

### Data the model depends on

| Field | Why |
|---|---|
| `participant.age_years` | Target for calibration and validation. Setup cannot continue on the default age. |
| `mode`, `prior_sessions` | Select first full sessions; practice makes repeat scores look younger. |
| `device.device_id`, `device.model` | Check for offsets between headsets before pooling them. |
| `participant.height_cm`, `posture` | Reach and lean scale with body size; seated play skips the standing games. |
| `gravity_scale` (Stick Drop) | Catch latency uses trials at 0.75 g or faster, with drops ranked slowest. |
| `cue` (Spatial Tracking) | Balanced by design; kept so reaction time can be split by cue. |

## v1, fitted on hackathon data

- Ridge regression, chronological age as target, features from `features.md`.
- Leave-one-out CV. Report MAE, Pearson r, and the predict-the-mean baseline MAE.
- Age gap = predicted minus chronological. Report correlation of gap with age to check regression to the mean, and apply the standard linear bias correction.

## Done

`make features` prints functional age per session. A model card in `ml/MODEL_CARD.md` lists n, age range, metrics and limits.
