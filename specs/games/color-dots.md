# Color Dots

Code: `Games/ColorDotsGame.swift`. Metrics: `ScoreKit/Metrics/ColorDotsMetrics.swift`. Task: `color_dots`.

Spatial recall with a decision at every touch. Some dots light up around you, then every dot turns grey beside decoys and you touch only the ones that lit. The dots spread wider than the field of view, so study and recall both need head turns.

## Layout

Each trial places set size + 4 dots (4 cm radius) around the dominant shoulder: azimuth -100 to +100 degrees (0 is the start direction, positive is right), elevation -10 to +20 degrees, reach 0.45 to 0.55 m, at least 15 cm between centers. One dot per evenly spaced azimuth slot, jittered inside its slot, so the whole arc is covered at every set size. A fresh layout every trial, drawn from the block seed along with which dots light. If sampling cannot meet the 15 cm gap, a two row zigzag layout (rows 20 degrees apart) takes over, which always meets it.

## Flow

1. Study. The set size chosen dots glow blue (`go`) and each plays a soft note from where it sits. The other dots sit dim grey. Lasts 1.5 s plus 0.5 s per lit dot. Nothing is touchable. `study_start_t` is the first frame the dots are in the scene.
2. Every dot turns grey at once. The first frame of the grey scene is `recall_start_t`.
3. Recall. All dots breathe and glow as a fingertip nears. A touch is the nearest fingertip within the dot radius plus 1 cm (`ReachTrial.contactSlack`). Each dot can be touched once. A lit dot pops white, a decoy flashes orange for 150 ms and then sinks. `touched` and `touch_t` log every touch in order. The time is the hand sample time, never before `recall_start_t`.
4. Recall ends when touches reach the set size, at 2 false taps, or after 6 s plus 1.5 s per lit dot. `hits`, `false_taps`, `misses` (set size minus hits). Lit dots nobody found sink, untouched decoys dissolve, then a 0.8 s pause.

`max_head_turn_deg` is the largest head yaw away from the start direction during recall, from the head's forward vector flattened onto the floor (the projection `Rig` uses). It is logged for analysis and not scored. `tracking_gap_ms` is the worse of the two hands' longest gaps over the recall window. No numbers on screen during play.

## Staircase

1 familiarization trial at set size 2, 10 scored. Scored starts at set size 3. After a perfect trial (every lit dot touched, no false tap) the set size goes up one, capped at 8. After any other trial it goes down one, floored at 2. A trial shows 6 to 12 dots.

## Metrics

Scored blocks only. Trials with `tracking_gap_ms > 100` are dropped. Memory: `dots_span`, `dots_accuracy`. Decision: `dots_false_rate`, `dots_decision_time`.

- `dots_span`: largest set size among kept trials that were perfect. n is kept trials, sem 0.5 (half a step, as Corsi span). Omitted when no kept trial was perfect.
- `dots_accuracy`: mean over kept trials of max(0, hits - false taps) / set size. sem is the standard error of that mean, from 2 trials up.
- `dots_false_rate`: false taps over touches (hits + false taps), pooled over kept trials. n is touches, sem as Gate (Agresti-Coull). Omitted when there were no touches.
- `dots_decision_time`: robust median, over kept trials with a touch, of the first touch time minus `recall_start_t`, in seconds. Shown as "Recall start time".

## Open

- The gap rule takes the worse hand, so a hand that stays out of tracking for the whole window drops the trial even if the other hand did all the work. The reach games take the touching hand, or the better hand when nothing was touched (`maxGapMs(nil, ...)`).
- A fingertip already inside a dot when the dots go grey touches it on the first frame, logged at `recall_start_t`. A dot is touched once, so there is no re-arm distance as in Constellation, and nothing arms at the start of recall either.
- Norm levels for all four metrics are placeholders (`NormTable.provisional`).
