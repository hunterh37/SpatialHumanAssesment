# Spatial Human Assessment PRD

Status: hackathon draft, v0.2 (4 October 2026), updated with the 12:27 to 12:37 team decisions. Builds on v0.1; its outputs, stretch goals, privacy rules, risks and workstreams are kept below. Concept deck: `concept/SpatialReactionMemory_Concept.pdf`.

## Summary (STAR)

**Situation.** Sundai Hack 143, Biomarkers of Aging, runs Sunday 4 October 2026, 10:00 to 22:00 at Harvard, as part of Boston Longevity Week ([event page](https://www.sundai.club/events/boston/sundai-hack-143-biomarkers-of-aging-hack), [Boston Longevity Hub](https://bostonlongevity.org/)). Teams formed at 11:00, card votes close at 8:15 PM, and final presentations start at 20:00. Most aging clocks need blood or a lab.

**Task.** Build, in one day, a Vision Pro game that estimates a player's movement age from how they move, and make it fun enough to repeat.

**Action.**

1. Hunter set up this repo: visionOS app, session schema, ingest service, Python age model and live dashboard.
2. Research lanes pulled published norms for reaction, reach, balance, chair stands and shoulder range, plus headset accuracy and claim limits.
3. Build in Xcode 26.2 with the visionOS 26.2 SDK: `brew install xcodegen`, set `DEVELOPMENT_TEAM` in `apps/vision/project.yml` locally, then `make app`. Command-line builds also need `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
4. Run on two paired Vision Pros with Developer Mode on, or on the visionOS simulator once its runtime is downloaded in Xcode settings.
5. Hunter shares a `mini-catalog` branch with the app shell. Every change goes on its own branch and merges by PR; schema changes bump the version.
6. Collect 20 or more sessions at the event, fit the v1 model, and post the card by 19:45.

**Result (target).** Two Vision Pros duel side by side. Each player sees their current movement age, and levelling up trains reaction, memory and balance, abilities linked to falls and mortality, moving them toward a younger movement age.

- **Card line (draft):** How old do you move? Two players, two Vision Pros, one 6-minute duel that scores your movement age against published norms.
- **Adds to v0.1:** the 12:00 brainstorm (head-to-head play, levelling up) and the 12:37 split: Hunter builds the catch game and a hand x-ray, Wilson builds the memory and balance games.
- **Movement age** is the player-facing name for the spec's `functional_age` field.
- **Team:** skylarwooster (idea lead), Hunter, Jess, bw2, Xelaf, franco, Wilson.

## ELI5: how it works

You and a friend play four quick games in Vision Pro. The headset times your reactions, measures how far you reach and how steady you stay, and checks what you remember. We match your scores against published results from people of every age, and the age you match is your movement age. Play again, get better, and watch it drop.

![One loop: play, measure, compare, level up](docs/eli5/movement-age-loop.svg)

![Your time lands on the age line](docs/eli5/age-curve.svg)

## Answers to the team to-do list

Proposed answers from the 12:27 to 12:37 team discussion, for the team to confirm.

| Question | Proposed answer | Why |
|---|---|---|
| Name | **SpatialAge**; alternatives: Movement Age, AgeDuel | It is already the app target in `apps/vision/SpatialAge`, so there is no rename. Check the App Store and trademarks before any launch |
| Branding | The concept deck look: warm paper, navy ink, blue for go targets, orange for no-go, Helvetica. Hook line: **How old do you move?** | It matches the figures already in the repo, and a question makes no health claim |
| Target audience | **Clinics first:** patients play in the waiting room and staff see trends between visits. Consumers second, through head-to-head duels | The team already works with clinicians, and one clinic headset serves many patients |
| Business use case | Waiting-room assessment as a per-clinic subscription, with the duel as the engagement layer that brings patients back | Repeat visits give the trend that one test cannot. If clinicians use scores for care decisions, the product moves toward FDA device rules, so keep it framed as wellness and check with counsel |
| Final design | Four games in about 6 minutes: Catch the knives (reaction, Hunter), Color dots (memory and decisions, Wilson), Reach and grab plus Hole in the wall (reach and balance in the Wii Fit U style, Wilson, from alex's ideas). Bonus: hand x-ray (Hunter). The result screen shows movement age per game and overall, then level up | It matches the 12:37 split and the ELI5 loop above |
| Metrics (data) | Catch: reaction and movement time (ms), misses. Color dots: hits, false taps, misses, decision time (ms), head turn (degrees). Reach and grab: furthest object grabbed and head travel (cm). Hole in the wall: pose match, hand drift and head sway during each hold (cm), walls cleared. Per session: movement age per game and overall, valid trial rate | These fields go into the session schema; norm sources are in the Movement Age engine table |

## Problem

Reaction time, reach and balance predict falls and mortality, yet people measure them only in clinics and labs, with tests too dull to repeat. Blood and epigenetic clocks need a lab. Vision Pro already tracks hands, head and the room, so a short game can measure these anywhere.

| Evidence | Finding | Source |
|---|---|---|
| Reaction time | 1 SD slower reaction time: all-cause mortality HR 1.25, cardiovascular HR 1.36; 5,134 US adults aged 20 to 59 | [NHANES cohort](https://pmc.ncbi.nlm.nih.gov/articles/PMC3906008/) |
| Reach | Unable to reach: odds ratio 8.07 for recurrent falls; reach of 6 inches or less: 4.02; 217 men aged 70 to 104 | [Veterans reach cohort, 1992](https://pubmed.ncbi.nlm.nih.gov/1573190/) |
| Balance | Failing a 10-second one-leg stand: mortality HR 1.84; 1,702 adults aged 51 to 75 | [Araujo 2022, BJSM](https://pubmed.ncbi.nlm.nih.gov/35728834/) |
| Training | Stepping programs cut falls about 50% (rate ratio 0.48; 7 trials, 660 people) and improved stepping reaction time | [Okubo 2017 meta-analysis](https://pubmed.ncbi.nlm.nih.gov/26746905/) |
| Engagement | Competition raised daily steps the most of three game mechanics (920 more than control; 602 adults) and was the only lasting effect | [STEP UP RCT](https://pubmed.ncbi.nlm.nih.gov/31498375/) |

The link is association, not proof: no trial shows that raising these scores lowers mortality.

## Users and personas

Clinics come first: patients play in the waiting room and staff see trends. Consumers come second, through head-to-head duels at home.

| Persona | Who | Job to be done | What they get |
|---|---|---|---|
| Clinic patient (primary) | Adult waiting for an appointment | While I wait, I want a quick game that shows how my reaction, memory and balance are doing | A movement age per game and progress since the last visit |
| Clinic staff (buyer) | Clinicians and front-desk staff | Get a repeatable movement check without extra appointment time | Trends between visits, never a diagnosis |
| Player (consumer) | Adult who duels a friend at home | When I play a friend, I want to see whose movement age is younger and keep improving | Round wins, levels, a movement age |
| Operator (hack day) | Team member running sessions | Start a duel fast and link sessions without names | Participant codes; age, sex and handedness entry; a consent screen |
| Audience (hack day) | Sundai voters | Follow the duel live | The AirPlay mirror plus the live dashboard |

## Goals and success metrics

**Primary metric:** 20 or more valid sessions collected at the event across a wide age range, each with a movement age.

| Secondary metric | Target |
|---|---|
| Full duel, start to result | 6 minutes or less |
| Session to features and movement age | Under 5 seconds |
| Model accuracy | Leave-one-out MAE reported next to a predict-the-mean baseline |
| Sundai card live with a real-frame thumbnail | By 19:45 |

**Guardrails:** sessions with a valid trial rate under 0.7 are flagged and excluded from training, and no names are stored.

**Non-goals:**

- Clinical claims, diagnosis or a biological age.
- Accounts, cloud storage and an App Store release.
- Raw gaze, which visionOS does not expose to apps.
- Upper-body strength, which needs a weight or a band.
- Finger-joint angles and tremor: finger-angle error was 9.6 degrees on Quest 2 ([source](https://pmc.ncbi.nlm.nih.gov/articles/PMC10830632/)), and no headset tremor validation was found.

## Product

A duel is a set of short games in mixed reality. Both players run the same games, each game awards a point, and the result screen shows both movement ages. The headset sees the head and both hands only, so every game reads through them (`specs/architecture.md`).

| Game | Metric | What players do | What the headset measures | Owner |
|---|---|---|---|---|
| Warm-up | None | One unscored practice pass per game | Nothing scored | Each game's owner |
| Catch the knives | Reaction | Catch knives as they fall | Movement onset and catch time, using the [simple reaction](specs/tasks/simple-reaction.md) timing rules | Hunter |
| Color dots | Memory and decisions | Colored dots appear around the room; tap the ones you were shown and skip the rest | Taps and skips, decision time, how far you look around | Wilson |
| Reach and grab | Reach and mobility | Feet planted, reach out and tap to pick up virtual objects placed farther and farther away; leaning is fine, stepping is not | Furthest object grabbed and head travel, in cm. Reaching farther means moving more freely | Wilson |
| Hole in the wall | Balance and stability | A wall with a cutout moves toward you; strike the pose and hold it still until the wall passes; move and you hit the wall | Pose match, hand drift and head sway during each hold, walls cleared | Wilson |
| Hand x-ray | Demo | A separate app that shows an x-ray view of your own hand | Hand skeleton from hand tracking | Hunter |
| Chair sprint, one-leg hold | Strength, balance | Not built today | Reps from head height; hold time | Unassigned |

- **Where the code goes:** Hunter shares a `mini-catalog` branch with the app shell that holds the games. Wilson's Color dots, Reach and grab and Hole in the wall games land on it as PRs. Reach and grab and Hole in the wall are alex's ideas, and his Freeze idea (move and you get caught) becomes the hold rule inside Hole in the wall.
- **Head-to-head:** two headsets in sync, or one headset taken in turns (open question). The same hardware for both players cancels device latency between them.
- **Levelling:** each duel earns XP. Each metric shows change against the player's own first session, and only changes larger than test-retest noise count.
- **Safe balance:** both balance games keep both feet on the floor, so players find their limits before a fall. The design reference is the [Wii Fit U balance games](https://www.youtube.com/watch?v=ybKOF1_yLZg): players steer by shifting their weight. With no balance board, the headset's head position stands in for the center of balance; head position and force-plate sway agree only moderately to well, so the game calibrates on this headset.
- **One-leg hold:** left out for safety, although failing a 10-second stand carried mortality HR 1.84 ([Araujo 2022](https://pubmed.ncbi.nlm.nih.gov/35728834/)). It could return later with a spotter.
- **Strength and mobility:** strength is unassigned. Reach and grab now covers mobility; neck rotation from headset orientation is a validated extra: ICC above 0.95 against motion capture ([source](https://pmc.ncbi.nlm.nih.gov/articles/PMC10747215/)).
- **Safety:** passthrough stays on, the floor stays clear, and one tap skips any game.

## Outputs

Per session from v0.1: reaction time, movement time, decision time, reaction time variability, commission and omission rates, Corsi span, reach time by target eccentricity, functional age, and age gap (functional minus chronological). Definitions live in `specs/features.md`. The new games add color-dot hits, false taps, misses and head turn; furthest grab distance; and pose match, hand drift, head sway and walls cleared during holds. Their feature definitions still need specs.

## Movement Age engine

Movement age combines published age slopes with an anchor measured on this headset. Published norms say how much each measure changes per decade, and event sessions set the starting point on Vision Pro. Lab norms cannot be read directly: simple reaction time averaged 0.48 s in VR against 0.27 s on a PC in the same 66 people ([source](https://pmc.ncbi.nlm.nih.gov/articles/PMC12976848/)), and Vision Pro hand tracking measured about 128 ms of latency on visionOS 1.1.1 ([Road to VR](https://roadtovr.com/apple-vision-pro-meta-quest-3-hand-tracking-latency-comparison/)).

1. **Score:** each feature becomes a z-score against the event's young-adult reference on this device.
2. **Convert:** the published slope for that measure turns the z-score into years.
3. **Combine:** movement age = reference age + the weighted mean of those years, as in `ml/sha_biomarkers/norms.py` v0. Every constant cites its source on the same line.
4. **Fit (v1):** ridge regression on event sessions, with leave-one-out CV and a linear bias correction (`specs/age-model.md`).

| Metric | Feature | Published norms | Status |
|---|---|---|---|
| Strength | 30 s chair-stand reps | [Colombian multicenter 2025](https://pubmed.ncbi.nlm.nih.gov/42183074/): percentiles by sex in six bands from 18-29 to 70-80. Its equation, reps = 26.458 - 0.171 x age - 1.394 x sex, has R2 0.258, so a chair-stand age alone is noisy | Verified |
| Balance | Hole in the wall: hand drift and head sway during holds | [Posturography sway norms](https://pmc.ncbi.nlm.nih.gov/articles/PMC12926707/): 250 adults in five bands from 25-40 to 76-80. These are force-plate numbers, so the headset needs its own calibration | Pending |
| Reach | Reach and grab: furthest grab, cm | [Nakhostin-Ansari 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9422043/): functional reach in six bands from 18-29 to 70+ | Verified |
| Reaction | Simple and choice reaction time, decision time | [Tap reaction time on a Wii Balance Board](https://pmc.ncbi.nlm.nih.gov/articles/PMC5747451/): percentiles by sex per decade from 20-29 to 80+, 354 adults. Slopes: choice reaction time rose 2.80 ms a year from 18 to 65 ([1,466 adults](https://pmc.ncbi.nlm.nih.gov/articles/PMC4407573/)); simple reaction time averaged 290, 318 and 354 ms at ages 30, 50 and 69 ([2,196 adults](https://pmc.ncbi.nlm.nih.gov/articles/PMC5608941/)). Use slopes, never lab milliseconds | Verified |
| Mobility | Arm or neck angle, degrees | [Shoulder range norms](https://pmc.ncbi.nlm.nih.gov/articles/PMC7549223/): flexion, abduction and external rotation by sex in 5-year bands from 20-24 to 85+, 2,404 adults; right flexion fell 43 degrees in men. No headset arm-angle validation found | Pending |
| Memory | Color-dot recall: hits, false taps, decision time | Not yet searched. Decision time can borrow the choice reaction slope above | Pending |

**Level-up curve:** a metric counts as improved only when it beats the player's own baseline by more than test-retest noise. A Quest 3 reaction task had single-trial ICC 0.80 to 0.88, and mixed and full VR scores differed by up to about 110 ms, so each player is compared in one environment ([source](https://pmc.ncbi.nlm.nih.gov/articles/PMC13568001/)).

## Requirements and user stories

**Epic hypothesis:** we believe a head-to-head duel that scores a movement age will get people to repeat a functional assessment, because competition was the strongest game mechanic and the only lasting one in a 602-person trial. It works if 20 or more event sessions produce a valid movement age and 5 or more players come back for a second duel.

**1. Start a duel.** As an operator, I want to enter two players and start a duel, so sessions link without names.

- [ ] Random participant codes; age, sex and handedness entered; no names stored
- [ ] Consent screen before the first game
- [ ] Session JSON validates against `packages/schema/session.schema.json`

**2. Catch duel.** As a player, I want to catch falling knives before my opponent, so reaction time feels like a game.

- [ ] Reaction time = hand movement onset minus drop start; movement time = onset to catch
- [ ] Trials with a tracking gap over 100 ms are dropped
- [ ] The first clean catch wins the point

**3. Balance games.** As a player, I want a safe way to see how far I can reach and how still I can hold, long before balance becomes a fall.

- [ ] Reach and grab: virtual objects sit at growing distances and a tap picks each up, feet planted; score = furthest object grabbed, in cm
- [ ] Hole in the wall: a wall with a cutout moves toward the player; head and hands must match the cutout and hold still until it passes; moving past a sway threshold hits the wall; score = pose match, hand drift, head sway and walls cleared
- [ ] One tap skips a game for anyone unsteady

**4. Color-dot memory.** As a player, I want to remember which colored dots appeared around me and tap only those, so one game checks memory, looking around and decisions.

- [ ] Dots appear around the room, some behind the player, so finding them takes a head turn
- [ ] Every dot tapped or skipped is logged: hits, false taps and misses
- [ ] Decision time and how far the head turned are logged per dot

**5. Movement age result.** As a player, I want my movement age per game and overall, so I know where I stand.

- [ ] Each game shows its value, its movement age and its norm source
- [ ] Wording says movement age and game score, never biological age or a health claim
- [ ] The result appears within 5 seconds of the last game

**6. Level up.** As a returning player, I want to see progress against my first session, so improvement feels real.

- [ ] Change shows only when larger than test-retest noise
- [ ] XP and level are stored by participant code only

**7. Live dashboard.** As an audience member, I want to follow the duel live.

- [ ] Last reaction time shown large, plus both players' game scores
- [ ] Under 500 ms lag on local wifi (`specs/dashboard.md`)

**Constraints:** Vision Pro gives head and hand tracking only, with no body or gaze data. Headset pose error averaged 0.52 cm relative and 3.62 cm absolute against motion capture ([preprint](https://arxiv.org/html/2508.08642v1)), so reach and sway are scored relative to the start pose. No Vision Pro fingertip accuracy figure was found; Quest 2 measured 1.1 cm ([source](https://pmc.ncbi.nlm.nih.gov/articles/PMC10830632/)).

## Strategic context and guardrails

Movement age is a game score against published norms. It is not a biological age, a diagnosis or a health claim.

**Precedent:** Wii Fit already showed players a Wii Fit Age on a 2 to 99 scale, where 46 meant the balance of an average 46-year-old ([review](https://pubmed.ncbi.nlm.nih.gov/24507245/)). Nintendo lists Wii Fit at 22.67 million units ([Nintendo IR](https://www.nintendo.co.jp/ir/en/sale/software/wii.html)). The same review found Wii Fit's software balance scores far less effective at judging balance, so ours must be checked against reference measures.

**Opening:** no head-to-head fitness game was found on Vision Pro. Quest already has live player-vs-player fitness ([ChallengeBox Fitness](https://www.meta.com/experiences/challengebox-fitness/7677012659036198/), store listing, not code-verified), so we stand apart on the measured movement age.

| We can say | We cannot say |
|---|---|
| Your reaction time matches a typical 34-year-old's on this test | You are biologically 34 |
| Slower reaction time is linked to higher mortality in large cohorts | Playing lowers your mortality |
| Balance training cut falls in trials of older adults | This game prevents falls |
| A general wellness game for staying active | It diagnoses, treats or prevents any disease |

**Why the line sits there:** FDA's general wellness policy covers healthy-lifestyle software unrelated to diagnosing or treating disease ([FDA](https://www.fda.gov/regulatory-information/search-fda-guidance-documents/general-wellness-policy-low-risk-devices)). The FTC made Lumosity pay $2 million, with a $50 million judgment suspended, over claims its games delay age-related decline ([FTC](https://www.ftc.gov/news-events/news/press-releases/2016/01/lumosity-pay-2-million-settle-ftc-deceptive-advertising-charges-its-brain-training-program)). This is not legal advice; get counsel before anything ships beyond the hack.

## Architecture and ownership

Data flow is in `specs/architecture.md`: each headset posts one session file to the ingest service on the laptop (port 8787), which scores it with `ml` and streams results to the dashboard. Whether the two headsets sync through SharePlay is an open question. Owners are proposed until the team confirms them.

| Area | Path | Spec | Owner (proposed) |
|---|---|---|---|
| App shell (`mini-catalog`), catch game, hand x-ray, two-player sync | `apps/vision` | `specs/tasks/*`, `specs/architecture.md` | Hunter |
| Color dots, Reach and grab, Hole in the wall | `apps/vision` | New specs needed | Wilson |
| Session contract | `packages/schema` | `specs/session-schema.md` | Shared |
| Features, cited norms, movement age | `ml` | `specs/features.md`, `specs/age-model.md` | Wilson |
| Ingest service | `services/ingest` | `specs/architecture.md` | Open |
| Live dashboard | `apps/dashboard` | `specs/dashboard.md` | Open |

The schema is the contract between all areas. Changing it needs a version bump and a note in `specs/session-schema.md`.

## Hack-day plan

Times are Boston time and stay targets until the team confirms them.

| Time | Milestone |
|---|---|
| 12:45 | Scope agreed (done at 12:37) |
| 13:00 to 14:30 | PRs: games on `mini-catalog`, schema, norms |
| 14:30 | First duel on two headsets |
| 15:00 to 18:00 | Collect 20+ sessions |
| 18:15 | Fit the v1 model and write the model card |
| 19:00 | Card draft with a real-frame thumbnail |
| 19:45 | Card live; team in the room voting |
| 20:00 | Final presentations |
| 20:15 | Votes close |

The 19:45 card time follows Wilson's analysis of the public Sundai projects API. At Hack 142, 64 of 67 likes landed between 19:49 and 20:20, and cards without a thumbnail reached the top 3 only 1% of the time.

## Stretch

HealthKit join (resting HR, HRV, VO2 max) where the participant consents. Head-turn kinematics. Test-retest on 5 participants.

## Privacy

No names. A random participant code links sessions. Data stays on the operator laptop under `data/`, which git ignores. Consent screen before the first task.

## Risks and open questions

| Risk | Mitigation |
|---|---|
| Headset reaction time runs slower than lab tests: 0.48 s in VR against 0.27 s on a PC | Anchor on this device and use published slopes only |
| Vision Pro hand-tracking latency, about 128 ms on visionOS 1.1.1 | Same hardware for both players; re-measure on visionOS 26 |
| Hand tracking dropouts | Log tracking state per frame, drop trials with gaps over 100 ms |
| A player loses balance during the balance games | Both feet on the floor, passthrough on, clear floor, one-tap skip |
| Practice effects inflate repeat scores | Fixed warm-up; level-ups only beyond test-retest noise |
| A small sample overfits the v1 model | Few features, ridge regression, literature priors, leave-one-out CV |
| Room too small for placement | Fallback spawn shell 0.4 to 0.7 m around the user |
| Claims drift on the card | Use the wording table in Strategic context and guardrails |
| Session data in a public repo | `data/` stays git ignored; random codes only, no names |

**Open questions**

- [ ] Confirm the proposed name, branding, audience and business use case above
- [ ] Two headsets in sync through SharePlay, or one headset taken in turns?
- [ ] Repo access for Jess (GitHub jess-myles)
- [ ] Who leads the Sundai card, and which real frame becomes the thumbnail?
- [ ] Age norms for color-dot memory, searched before the age engine scores it
- [ ] Hand-tracking latency on visionOS 26, measured before trusting absolute reaction times

## Sources

Sources are linked where they are used. In a code check, 22 of 24 quotes from today's research matched their sources. The Quest 2 accuracy quote was then confirmed against its Europe PMC abstract. The ChallengeBox store page blocks scripted fetches. Event facts and the chair-stand, balance and reach norms come from an earlier verified research run the same morning. The ELI5 diagrams use the concept deck's style; the age line in Fig B plots the three published cohort means, and its example player is illustrative.
