# Features

Implemented in `ml/sha_biomarkers/features.py`. Scored blocks only. Trials with `tracking_gap_ms > 100` are dropped.

| Feature | Definition | Aging direction |
|---|---|---|
| `simple_rt_median` | median RT, simple hits | up |
| `simple_mt_median` | median MT, simple hits | up |
| `choice_rt_median` | median RT, choice hits | up |
| `decision_time` | `choice_rt_median - simple_rt_median` | up |
| `rt_cv` | SD / mean of simple RT | up |
| `commission_rate` | false alarms / choice trials | up |
| `omission_rate` | misses / go choice trials | up |
| `corsi_span` | see `tasks/corsi-3d.md` | down |
| `ecc_slope` | slope of total reach time (RT + MT) on eccentricity, seconds per 90 degrees | up |
| `valid_trial_rate` | kept / total trials | quality flag |

Sessions with `valid_trial_rate < 0.7` are flagged and excluded from training.

RT variability (`rt_cv`) is included because intra-individual variability rises with age independent of mean speed.
