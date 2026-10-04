Feature extraction and age model. Specs: `specs/features.md`, `specs/age-model.md`.

`sha_biomarkers/features.py` session to features (stdlib only).
`sha_biomarkers/norms.py` age-25 reference values and v0 functional age. Constants need citations.
`sha_biomarkers/kdm.py` Klemera-Doubal age from a biomarker matrix; literature parameters in `kdm_params.json`.
`sha_biomarkers/kdm_fit.py` refits KDM parameters on collected sessions with leave-one-out gating (`make kdm-fit`).
`sha_biomarkers/synth.py` synthetic sessions for development. Not for reporting accuracy.

Run from repo root: `make sample features test`. KDM ages from collected sessions: `make kdm`; refit on them: `make kdm-fit` (see `specs/age-model.md`).
