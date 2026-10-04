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

`python -m sha_biomarkers.kdm table.csv` prints estimates for a CSV with biomarker columns and an optional `age` column.

## v1, fitted on hackathon data

- Ridge regression, chronological age as target, features from `features.md`.
- Leave-one-out CV. Report MAE, Pearson r, and the predict-the-mean baseline MAE.
- Age gap = predicted minus chronological. Report correlation of gap with age to check regression to the mean, and apply the standard linear bias correction.

## Done

`make features` prints functional age per session. A model card in `ml/MODEL_CARD.md` lists n, age range, metrics and limits.
