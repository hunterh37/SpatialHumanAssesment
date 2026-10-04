PY ?= python3

.PHONY: sample features test ingest app showcase scorekit-test scorekit-synth scorekit-score concept-algo

sample:
	cd ml && $(PY) -m sha_biomarkers.synth --out ../data/synthetic --n 30

features:
	cd ml && $(PY) -m sha_biomarkers.features ../data/synthetic/*.json

test:
	cd ml && $(PY) -m unittest discover -s tests

ingest:
	cd services/ingest && $(PY) server.py

app:
	cd apps/vision && xcodegen generate && open SpatialAge.xcodeproj

SCOREKIT = packages/ScoreKit/.build/release/scorekit
CONCEPT_BUILD = concept/build

concept-algo:
	cd packages/ScoreKit && swift build -c release
	rm -rf $(CONCEPT_BUILD) && mkdir -p $(CONCEPT_BUILD)
	$(SCOREKIT) norms > $(CONCEPT_BUILD)/norms.json
	$(SCOREKIT) synth --out $(CONCEPT_BUILD)/syn --n 40 --seed 7
	$(SCOREKIT) history --out $(CONCEPT_BUILD)/hist
	$(SCOREKIT) score $(CONCEPT_BUILD)/syn/*.json > $(CONCEPT_BUILD)/reports.json
	$(SCOREKIT) pace $(CONCEPT_BUILD)/hist/*.json > $(CONCEPT_BUILD)/pace.json
	$(PY) concept/src/gen_algo.py

SK = cd packages/ScoreKit && swift run -c release scorekit

scorekit-test:
	cd packages/ScoreKit && swift test

scorekit-synth:
	$(SK) synth --n 40 --out ../../data/synthetic-minigames

scorekit-score:
	$(SK) score ../../data/synthetic-minigames/*.json

showcase:
	$(PY) showcase/src/build.py
