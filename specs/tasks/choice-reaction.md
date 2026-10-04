# Choice reaction

Adds a decision step. Decision time = median choice RT minus median simple RT.

## Flow

1. Familiarization: 5 trials.
2. Scored: 30 trials. 70 percent go (one blue plus one orange), 30 percent nogo (orange only).
3. Placement and timing as `simple-reaction.md`. Blue and orange sit at least 25 cm apart.
4. Window 2.0 s.

## Outcomes

| Trial | Response | Outcome |
|---|---|---|
| go | touch blue | `hit` |
| go | touch orange first | `false_alarm` |
| go | nothing | `miss` |
| nogo | touch orange | `false_alarm` |
| nogo | nothing | `correct_reject` |

## Done

30 scored trials logged. Outcomes match the table in unit tests.
