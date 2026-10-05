<p align="center"><img src="docs/brand/betteryears-mark-512.png" width="160" alt="BetterYears Age bird logo"></p>

# BetterYears Age (Spatial Human Assessment)

Eight Vision Pro minigames that measure reaction, decisions, reach, balance and spatial memory, and turn them into one "movement age" - your *BetterYears Age*.

Games: `specs/games/`.     
Score: `specs/score.md`.

## How it works

**How old do you move?** Put on a Vision Pro and play eight quick games. The headset tracks head and hands, each score is compared with published results from people of every age, and the age you match is your BetterYears Age. Play again, level up, and watch it drop, then compare scores with friends on the leaderboard. Your BetterYears Age is a game score against published norms, not a medical test.

![Four quick games](docs/eli5/games.svg)

![Your time lands on the age line](docs/eli5/age-curve.svg)

![One loop: play, measure, compare, level up](docs/eli5/movement-age-loop.svg)

All eight games are on `main` and in the app's Games grid. Names and lines are the in-app copy from `packages/ScoreKit/Sources/ScoreKit/Model/Game.swift`.

| Game | What you do | Measures | Built by |
|---|---|---|---|
| Stick Drop | Catch the falling leaf before it hits the ground. | Visual reaction time and useful field of view | Hunter, Jason |
| Spatial Tracking | Listen and look. Point at each falling leaf before it lands. | Audio and visual reaction time and localization | Hunter, Jason |
| Gate | Touch blue as fast as you can. Leave orange. | Decision time and inhibition | Hunter, Jason |
| Constellation | Watch the stars light, then touch them in order. | Spatial working memory span | Hunter |
| Orbit | Keep your fingertip inside the moving light. | Visuomotor tracking error and lag | Hunter |
| Scary Balance | Walk to the glowing spot and reach for the object. Freeze when the creature passes. | Reach, lean and holding still | Alex (design), Wilson, Hunter |
| Hole in the Wall | Stay on the island. Make the shape in the wall and hold it as the wall passes. | Arm mobility and pose holding | Alex (design), Wilson, Hunter |
| Spatial Memory | Touch the balls you are asked for. Then find the ones you did, or did not, touch. | Decision time and spatial memory | Alex (design), Wilson, Hunter |

**Situation.** Sundai Hack 143, Biomarkers of Aging, Harvard, Sunday 4 October 2026. Most aging clocks need blood or a lab.
**Task.** Build, in one day, a Vision Pro game that estimates BetterYears Age from how people move.
**Action.** A shared session schema, the visionOS minigame catalog, ScoreKit for scoring, and research-backed norms, built by PR on this repo.
**Result.** Each player plays solo in a calm 3D forest clearing, sees a BetterYears Age with an 80% interval, levels up as it drops, and compares scores with friends on the leaderboard.

**Team:** Jason and Hunter led the idea and each brought a Vision Pro; they built the app, the reaction games and the hand x-ray. Alex designed the brand, the Games Ideas deck, the Dusk spec and the Dusk Meadow, and made the Better Years Calm track (#27). Franco designed the scoring system and built the Klemera-Doubal age model and pipeline. Jess owns the business use case, the name and UI/UX. Ben mapped the Vision Pro app landscape and the age-norm references. Wilson wrote the PRD and research and built the first memory and balance games and the branding PRs. LinkedIn links are in the PRD under Team and ownership.

The full plan, sources and guardrails are in [PRD.md](PRD.md); the picture explainer is `docs/eli5/index.html`.

## How scoring works

Our *BetterYears Age* estimate is calculated using an algorithm inspired by the [Klemera-Doubal (KDM)](https://doi.org/10.1016/j.mad.2005.10.004) formula with Bayesian updating. Each game metric is treated as a biomarker with a known age curve. The player's age is the one that best explains all their metrics together. The norms start from priors derived from literature and are updated as real sessions occur.

1. **Measure.** Each game turns your movements into a few metrics, such as how fast you react, how well you decide, how closely you track a moving target and how much you remember.
2. **Compare with age curves.** For each number, published studies tell us what is typical at every age. Your result points to the age it best matches.
3. **Weigh the evidence.** KDM combines all your games into one age. Games that change strongly with age and are not too noisy count more; noisy or weakly age-related ones count less.
4. **Start from your real age.** Your chronological age acts as a starting guess. With little data, your BetterYears Age stays close to your chronological age; the more games you play, the more your own results influence your BetterYears Age. You see the result with a range, not just a single number.
5. **Learn from new players.** As sessions are collected, the age curves are adjusted toward what real players show, while unusual runs count less. A new version is kept only if it predicts age at least as well as the old one. This refit runs on the operator laptop (`make kdm-fit`); the app's on-screen age still uses the built-in literature curves.

In the app, ScoreKit also groups results into five areas (Speed, Decision, Control, Memory, Consistency) and tracks how your BetterYears Age changes over repeat sessions. Details: [`specs/score.md`](specs/score.md), [`specs/age-model.md`](specs/age-model.md).

## Media

- **[Full day in 30 s](media/betteryears-day-recap.mp4):** talks, build, headset tests, the product and demo night
- **[13 s presentation intro](media/betteryears-intro.mp4):** the read-aloud script is in [media/intro-script.txt](media/intro-script.txt)
- **[App screen recording](media/betteryears-demo-screen-recording.mp4):** intro, Buddy, Stick Drop, Spatial Memory, Hole in the Wall

More details are in [media/](media/). Music: "Better Years Calm" by Alex Fu.

## Repo layout

```
apps/vision        visionOS app (Swift, XcodeGen)
apps/dashboard     live audience dashboard (web)
services/ingest    receives sessions from the headset, pushes to dashboard
ml                 feature extraction, KDM age model and refit (Python)
packages/schema    session JSON schema and examples, shared by all
packages/ScoreKit  Swift scoring: metrics, norms, Spatial Age, pace of aging, CLI
packages/DuskEnvironment  forest clearing shown behind every game
showcase           showcase PDF and its build script
specs              specs per area
concept            original concept deck and figures
docs, media        explainer pages, brand assets, demo videos
research, notes    background research and build notes
data               local session files and KDM output, git ignored
```

Quick start without a headset:

```
make sample     # write synthetic sessions to data/synthetic
make features   # print features for each synthetic session
make test
make scorekit-test               # ScoreKit tests
make scorekit-synth              # synthetic eight-game sessions -> data/synthetic-minigames
make kdm SESSIONS=data/synthetic-minigames   # KDM ages -> data/kdm/ages.csv
```

With collected sessions in `data/sessions`, `make kdm` estimates ages and `make kdm-fit` refits the age curves.

Rules: branch per change, PR into `main`, one area per PR where possible. Schema changes need a version bump.
