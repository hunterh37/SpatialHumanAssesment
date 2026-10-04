# 3D Corsi

Measures spatial working memory span.

## Setup

9 cubes (8 cm) anchored on detected planes: table, shelf, seat, floor, wall. Spread over at least 120 degrees of azimuth so some need a head turn. Cube layout fixed for the whole session.

## Flow

1. Familiarization: one sequence of length 2.
2. Start at span 2. Light cubes one at a time, 0.8 s on, 0.2 s gap.
3. User touches cubes back in order. Touched cube flashes white.
4. Two correct at a span: span plus one. Two failures at a span: stop.
5. Hard cap: span 9 or 4 minutes.

Sequences never repeat a cube and are generated from a seeded RNG. Store the seed.

## Score

Corsi span = longest span with at least one correct sequence. Also log per-sequence response time.

## Done

Span and every sequence/response pair logged. Replay of a session from the log reproduces the score.
