import json
import random
import unittest

from sha_biomarkers.kdm import DEFAULT_PARAMS, KDM, Biomarker
from sha_biomarkers.kdm_fit import fitting_points, refit, update_biomarker

PRIOR = json.loads(DEFAULT_PARAMS.read_text())


def truth():
    """The headset reads 1.4x slower than the literature level, with the literature shape."""
    cfg = json.loads(json.dumps(PRIOR))
    for p in cfg["biomarkers"].values():
        if p["unit"] == "s":
            p["mean25"] *= 1.4; p["slope"] *= 1.4; p["accel"] *= 1.4
    return cfg


def matrix(n, seed=1, missing=0.0, cfg=None):
    """Matrix rows as csv.DictReader gives them: strings, empty for missing."""
    rng = random.Random(seed)
    bms = KDM.from_dict(cfg or truth()).biomarkers
    rows = []
    for i in range(n):
        age = rng.uniform(20, 80)
        r = {"session_id": f"S{i}", "code": f"P{i}", "started_at": f"2026-10-04T10:{i % 60:02d}:00Z",
             "age": f"{age:.0f}", "calibration": "1", "device_id": "D1"}
        for name, b in bms.items():
            r[name] = "" if rng.random() < missing else f"{b.expected(age) + rng.gauss(0, b.sd):.6g}"
        rows.append(r)
    return rows


class FitTests(unittest.TestCase):
    def test_first_session_per_code_and_partial_sessions(self):
        rows = [
            {"code": "A", "age": "30", "started_at": "2026-10-04T11:00:00Z", "choice_rt": "0.9"},
            {"code": "A", "age": "30", "started_at": "2026-10-04T10:00:00Z", "choice_rt": "0.5"},
            {"code": "B", "age": "60", "started_at": "2026-10-04T10:00:00Z", "choice_rt": ""},
            {"code": "B", "age": "60", "started_at": "2026-10-04T12:00:00Z", "choice_rt": "0.7"},
        ]
        self.assertEqual(sorted(fitting_points(rows, "choice_rt")), [(30.0, 0.5), (60.0, 0.7)])
        self.assertEqual(fitting_points(rows, "choice_rt", exclude_code="A"), [(60.0, 0.7)])

    def test_more_people_move_the_fit_further_from_the_prior(self):
        p = PRIOR["biomarkers"]["choice_rt"]
        target = truth()["biomarkers"]["choice_rt"]["mean25"]
        few, few_info = update_biomarker(p, fitting_points(matrix(8), "choice_rt"))
        many, many_info = update_biomarker(p, fitting_points(matrix(300), "choice_rt"))
        self.assertLess(abs(many["mean25"] - target), abs(few["mean25"] - target) + 1e-3)
        self.assertLess(abs(many["mean25"] - target), 0.02)
        self.assertGreater(many_info["data_weight_slope"], few_info["data_weight_slope"])

    def test_too_few_people_keep_the_prior(self):
        p = PRIOR["biomarkers"]["corsi_span"]
        out, info = update_biomarker(p, [(30.0, 5.0), (60.0, 4.0)])
        self.assertEqual(out["mean25"], p["mean25"])
        self.assertEqual(info["n"], 2)

    def test_refit_beats_literature_and_is_adopted(self):
        rows = matrix(40, seed=2, missing=0.3)
        cand, report, adopted = refit(PRIOR, PRIOR, rows)
        v = report["validation"]
        self.assertGreaterEqual(v["n"], 30)
        self.assertLess(v["mae_candidate"], v["mae_current"])
        self.assertTrue(adopted)
        self.assertIn("bias_correction", cand)
        self.assertTrue(cand["version"].startswith("fit-"))
        KDM.from_dict(cand)  # loads and stays monotone

    def test_not_adopted_without_enough_validation_people(self):
        rows = matrix(4, seed=3)
        _, report, adopted = refit(PRIOR, PRIOR, rows)
        self.assertFalse(adopted)
        self.assertTrue(refit(PRIOR, PRIOR, rows, force=True)[2])

    def test_partial_row_gets_wider_interval(self):
        m = KDM.from_dict(PRIOR)
        names = list(m.biomarkers)
        full = [m.biomarkers[n].expected(60) for n in names]
        one = [full[0]] + [None] * (len(names) - 1)
        e_full, e_one = m.predict([full, one], names)
        self.assertEqual(e_one.n, 1)
        self.assertGreater(e_one.se, e_full.se)

    def test_corrected_gap(self):
        m = KDM({"a": Biomarker("a", 10, 1, 0.2)})
        self.assertIsNone(m.corrected_gap(50, 40))
        m.bias = {"alpha": 5.0, "beta": -0.1}
        self.assertAlmostEqual(m.corrected_gap(50, 40), 10 - (5 - 4))


if __name__ == "__main__":
    unittest.main()
