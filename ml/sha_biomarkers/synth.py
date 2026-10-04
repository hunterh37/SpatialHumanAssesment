"""Synthetic sessions for building the pipeline and dashboard without a headset.

Effect sizes are invented. Never use synthetic data to report model accuracy.
"""
import argparse
import json
import pathlib
import random
import uuid


def _reaction_block(rng, task, n, age, familiarization):
    slow = 1 + 0.006 * (age - 25)
    t = 2.0
    trials = []
    for i in range(n):
        kind = "go" if task == "simple_rt" or rng.random() < 0.7 else "nogo"
        ecc = rng.uniform(0, 120)
        base = 0.30 if task == "simple_rt" else 0.43
        rt = max(0.15, rng.gauss(base * slow, 0.04 * slow))
        mt = max(0.1, rng.gauss(0.35 * slow + 0.1 * ecc / 90, 0.05))
        spawn = t + rng.uniform(0.8, 2.0)
        outcome = "hit"
        if kind == "nogo":
            outcome = "false_alarm" if rng.random() < 0.05 + 0.002 * age else "correct_reject"
        elif task == "choice_rt" and rng.random() < 0.03:
            outcome = "miss"
        moved = outcome in ("hit", "false_alarm")
        trials.append({
            "index": i,
            "kind": kind,
            "hand": "right" if moved else None,
            "spawn_t": round(spawn, 4),
            "move_t": round(spawn + rt, 4) if moved else None,
            "contact_t": round(spawn + rt + mt, 4) if moved else None,
            "position": [round(rng.uniform(-0.6, 0.6), 3), round(rng.uniform(0.8, 1.6), 3),
                         round(rng.uniform(-0.6, 0.6), 3)],
            "eccentricity_deg": round(ecc, 1),
            "outcome": outcome,
            "tracking_gap_ms": round(abs(rng.gauss(10, 20)), 1),
        })
        t = spawn + 2.5
    return {"task": task, "familiarization": familiarization, "trials": trials}


def _corsi_block(rng, age):
    true_span = 7 - (age - 25) / 25
    trials, span, idx = [], 2, 0
    while span <= 9:
        fails = 0
        for _ in range(2):
            seq = rng.sample(range(9), span)
            ok = rng.random() < 1 / (1 + 2.718 ** (2 * (span - true_span)))
            resp = seq if ok else seq[:-2] + seq[:-3:-1]
            trials.append({"index": idx, "span": span, "sequence": seq,
                           "response": resp, "correct": ok})
            idx += 1
            fails += not ok
        if fails == 2:
            break
        span += 1
    return {"task": "corsi", "familiarization": False, "seed": rng.randrange(2**31),
            "trials": trials}


def make_session(age: float, seed: int) -> dict:
    rng = random.Random(seed)
    return {
        "schema_version": "0.1.0",
        "session_id": str(uuid.UUID(int=rng.getrandbits(128))),
        "started_at": "2026-10-04T12:00:00Z",
        "participant": {"code": f"SYN{seed:03d}", "age_years": age,
                        "sex": "unspecified", "handedness": "right"},
        "device": {"model": "synthetic", "os_version": "-", "app_version": "-"},
        "blocks": [
            _reaction_block(rng, "simple_rt", 5, age, True),
            _reaction_block(rng, "simple_rt", 20, age, False),
            _reaction_block(rng, "choice_rt", 5, age, True),
            _reaction_block(rng, "choice_rt", 30, age, False),
            _corsi_block(rng, age),
        ],
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="../data/synthetic")
    p.add_argument("--n", type=int, default=30)
    args = p.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(0)
    for i in range(args.n):
        s = make_session(round(rng.uniform(18, 80)), i)
        (out / f"{s['participant']['code']}.json").write_text(json.dumps(s, indent=1))
    print(f"{args.n} sessions -> {out}")


if __name__ == "__main__":
    main()
