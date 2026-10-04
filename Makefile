PY ?= python3

.PHONY: sample features test ingest app

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
