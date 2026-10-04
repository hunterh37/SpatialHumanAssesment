# Age model

## v0, literature prior (works with zero data)

Each feature becomes a z-score against a reference mean and SD for age 25 (`ml/sha_biomarkers/norms.py`). Functional age = 25 + weighted sum of signed z-scores times years per SD. Constants are placeholders until replaced with values from published norms. Every constant cites its source in a comment.

## v1, fitted on hackathon data

- Ridge regression, chronological age as target, features from `features.md`.
- Leave-one-out CV. Report MAE, Pearson r, and the predict-the-mean baseline MAE.
- Age gap = predicted minus chronological. Report correlation of gap with age to check regression to the mean, and apply the standard linear bias correction.

## Done

`make features` prints functional age per session. A model card in `ml/MODEL_CARD.md` lists n, age range, metrics and limits.
