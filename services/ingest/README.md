Receives sessions from the headset, validates, stores in `data/sessions`, computes features, relays live events. Spec: `specs/architecture.md`.

```
pip install -r requirements.txt
make ingest          # http://<laptop-ip>:8787
curl -X POST localhost:8787/sessions -H 'content-type: application/json' \
  -d @../../packages/schema/examples/session.example.json
```

Live event format from the app over `WS /live`: `{"type":"trial_end","task":"simple_rt","index":3,"rt":0.31,"outcome":"hit"}`.
