"""Session JSON to feature dict. Definitions: specs/features.md."""
import json
import statistics
import sys

MAX_GAP_MS = 100


def _scored(session, task):
    for block in session["blocks"]:
        if block["task"] == task and not block["familiarization"]:
            yield from block["trials"]


def _valid(trial):
    return trial.get("tracking_gap_ms", 0) <= MAX_GAP_MS


def _median(xs):
    return statistics.median(xs) if xs else None


def _slope(xs, ys):
    if len(xs) < 3 or len(set(xs)) < 2:
        return None
    mx, my = statistics.fmean(xs), statistics.fmean(ys)
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den = sum((x - mx) ** 2 for x in xs)
    return num / den


def extract(session: dict) -> dict:
    total = kept = 0
    out = {}

    simple = [t for t in _scored(session, "simple_rt")]
    choice = [t for t in _scored(session, "choice_rt")]
    total += len(simple) + len(choice)
    simple = [t for t in simple if _valid(t)]
    choice = [t for t in choice if _valid(t)]
    kept += len(simple) + len(choice)

    s_hits = [t for t in simple if t["outcome"] == "hit" and t["move_t"] is not None]
    c_hits = [t for t in choice if t["outcome"] == "hit" and t["move_t"] is not None]
    s_rt = [t["move_t"] - t["spawn_t"] for t in s_hits]
    s_mt = [t["contact_t"] - t["move_t"] for t in s_hits]
    c_rt = [t["move_t"] - t["spawn_t"] for t in c_hits]

    out["simple_rt_median"] = _median(s_rt)
    out["simple_mt_median"] = _median(s_mt)
    out["choice_rt_median"] = _median(c_rt)
    out["decision_time"] = (
        out["choice_rt_median"] - out["simple_rt_median"]
        if out["choice_rt_median"] is not None and out["simple_rt_median"] is not None
        else None
    )
    out["rt_cv"] = (
        statistics.stdev(s_rt) / statistics.fmean(s_rt) if len(s_rt) > 2 else None
    )

    go = [t for t in choice if t["kind"] == "go"]
    out["commission_rate"] = (
        sum(t["outcome"] == "false_alarm" for t in choice) / len(choice) if choice else None
    )
    out["omission_rate"] = sum(t["outcome"] == "miss" for t in go) / len(go) if go else None

    ecc = [t["eccentricity_deg"] / 90.0 for t in s_hits]
    reach = [t["contact_t"] - t["spawn_t"] for t in s_hits]
    out["ecc_slope"] = _slope(ecc, reach)

    corsi = list(_scored(session, "corsi"))
    total += len(corsi)
    kept += len(corsi)
    passed = [t["span"] for t in corsi if t["correct"]]
    out["corsi_span"] = max(passed) if passed else (None if not corsi else 0)

    out["valid_trial_rate"] = kept / total if total else None
    return {k: (round(v, 4) if isinstance(v, float) else v) for k, v in out.items()}


def main(paths):
    from .norms import functional_age

    for path in paths:
        with open(path) as f:
            session = json.load(f)
        feats = extract(session)
        age = session["participant"]["age_years"]
        print(f"{session['participant']['code']}  age {age:>5}  "
              f"functional {functional_age(feats)}  {json.dumps(feats)}")


if __name__ == "__main__":
    main(sys.argv[1:])
