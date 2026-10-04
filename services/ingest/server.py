"""Ingest service. Spec: specs/architecture.md. Run: make ingest"""
import json
import pathlib
import sys

import jsonschema
import uvicorn
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ml"))
from sha_biomarkers import extract, functional_age  # noqa: E402

SCHEMA = json.loads((ROOT / "packages/schema/session.schema.json").read_text())
DATA = ROOT / "data/sessions"
DATA.mkdir(parents=True, exist_ok=True)
DASHBOARD = ROOT / "apps/dashboard/index.html"

app = FastAPI()
clients: set[WebSocket] = set()


async def broadcast(msg: dict):
    for ws in list(clients):
        try:
            await ws.send_json(msg)
        except Exception:
            clients.discard(ws)


def result(session: dict) -> dict:
    feats = extract(session)
    return {"session_id": session["session_id"], "participant": session["participant"],
            "features": feats, "functional_age": functional_age(feats)}


@app.get("/")
def dashboard():
    return FileResponse(DASHBOARD)


@app.post("/sessions")
async def post_session(session: dict):
    try:
        jsonschema.validate(session, SCHEMA)
    except jsonschema.ValidationError as e:
        raise HTTPException(422, e.message)
    (DATA / f"{session['session_id']}.json").write_text(json.dumps(session))
    res = result(session)
    await broadcast({"type": "result", **res})
    return res


@app.get("/sessions")
def list_sessions():
    return [result(json.loads(p.read_text())) for p in sorted(DATA.glob("*.json"))]


@app.get("/sessions/{session_id}")
def get_session(session_id: str):
    p = DATA / f"{session_id}.json"
    if not p.exists():
        raise HTTPException(404)
    s = json.loads(p.read_text())
    return {"session": s, **result(s)}


@app.websocket("/live")
async def live(ws: WebSocket):
    """App sends trial events here; every message is relayed to all other clients."""
    await ws.accept()
    clients.add(ws)
    try:
        while True:
            msg = await ws.receive_json()
            for other in list(clients - {ws}):
                await other.send_json(msg)
    except WebSocketDisconnect:
        clients.discard(ws)


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8787)
