# First-run setup (onboarding) mockup

Clickable prototype of the SpatialAge first-run setup, styled with the Dusk theme (`concept/SpatialAge_Dusk_Design_Spec.pdf`). Open `index.html` in a browser; it is a single self-contained file.

## Flow

One question per screen, one primary button per screen:

1. Welcome: "How old do you move?"
2. Consent (PRD requires a consent screen before the first game)
3. First name
4. Age (stepper plus slider)
5. Sex (female, male, other, prefer not to say)
6. Height (ft/in or cm)
7. Weight (lb or kg, skippable)
8. Main hand (left, both, right)
9. Standing or seated
10. Review with per-field Edit, then "Go to home"

## Data mapping

| Screen | Field | Status |
|---|---|---|
| First name | not saved | Greets the player during setup only. The Dusk spec says never store names, so it is never written to the session. |
| Age | `participant.age_years` | Existing, required |
| Sex | `participant.sex` | Existing, optional |
| Main hand | `participant.handedness` | Existing, optional |
| Height | `participant.height_cm` | Proposed new field |
| Weight | `participant.weight_kg` | Proposed new field, skippable |
| Standing or seated | `participant.posture` | Proposed new field; seated skips Reach and Grab and Hole in the Wall |
| (automatic) | `participant.code` | Existing, required |

The three proposed fields are not added to `packages/schema/session.schema.json` in this PR. Adding them needs a schema version bump (repo rule) and sign-off from schema owners.

## Dusk spec checklist

- Only Dusk tokens; signal colors untouched and not used for decoration (gold only on the current progress dot, as the spec allows)
- One primary (peach) button per screen; Back is an icon button, Skip is tertiary
- Hit targets 60 pt or more with 16 pt spacing
- Copy says "movement age", no exclamation marks, no medical claims
- Reduce Motion respected
