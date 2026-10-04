# Spatial Memory

Code: `Games/ColorDotsGame.swift`. Metrics: `ScoreKit/Metrics/ColorDotsMetrics.swift`. Task: `color_dots` (name kept from the earlier Color Dots game).

Deck: items surround the participant. Instructions say to select only certain items (color, size). Then the participant selects either every ball they DID select or every ball they DID NOT. Tests decision time and spatial memory.

## Layout

Rule targets `n` (staircased) plus `n + 2` distractors, all balls. Azimuth -135 to +135 degrees around the head (behind the shoulders, so the body turns), elevation -10 to +20 degrees from shoulder height, reach 0.45 to 0.55 m, at least 16 cm between centers, one ball per evenly spaced azimuth slot. Colors: blue, orange, yellow, green. Sizes: small 3.2 cm, big 5.2 cm radius.

Rules alternate by trial:

- `color:<name>`: targets share one color; distractors take the other colors; sizes random.
- `size:large`: targets are big; distractors small; colors random.

## Flow

1. Select. HUD: "Touch every blue ball." (or "every big ball"). Each touch marks the ball with a ring and a tick and the ball stays. The mark is the same for a right or wrong pick. Select ends at `n` touches or after 5 s + 1.5 s per target. `study_start_t` is the first frame of the balls; `selected` and `select_t` log the picks.
2. Grey out after 0.6 s: every ball turns grey and 4.2 cm, so only place is left.
3. Recall. HUD: "Now touch every ball you DID touch." or "...DID NOT touch." Modes are balanced and shuffled; practice asks DID. The answers (`shown`) come from what was picked in select, not from the rule. A right touch pops, a wrong one flashes orange and sinks. Recall ends when every answer is found, at 2 false taps, or after 6 s + 1.5 s per answer. `set_size` is the answer count.

## Staircase

1 familiarization at 2 targets, 10 scored starting at 3. A perfect recall raises targets by one (max 6), anything else lowers it (min 2).

## Metrics

- `dots_span`: most rule targets in a perfect recall (from `rule_match`; sessions before 0.4 use `set_size`).
- `dots_accuracy`, `dots_false_rate`, `dots_decision_time` (first recall touch from grey out): as before, on the recall phase.
- `dots_select_time`: robust median time per select touch, the first from select start, the rest touch to touch. Decision domain.

## Open

- Select accuracy against the rule (`selected` vs `rule_match`) is logged and not scored yet.
- Norm levels are placeholders (`NormTable.provisional`).
