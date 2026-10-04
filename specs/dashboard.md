# Dashboard

Browser page for the audience, shown next to the AirPlay mirror.

## Live view

- Current task and trial counter.
- RT of the last trial as a large number, plus a running strip of recent RTs.
- Corsi: current span and pass/fail per sequence.

## Result view

- Feature table with participant value against the age-25 reference.
- Participant dot on age curves for RT and Corsi span (curves from `ml` norms).
- Functional age and age gap.
- Leaderboard of anonymous codes by reaction time.

## Tech

Single static HTML + JS file, served by ingest at `/`. Connects to `WS /live`. No build step.

## Done

Full session plays live on the dashboard with under 500 ms lag on local wifi.
