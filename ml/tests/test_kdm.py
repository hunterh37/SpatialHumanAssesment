import json
import math
import random
import unittest

from sha_biomarkers.kdm import DEFAULT_PARAMS, KDM, Biomarker, fit

LINEAR = {
    "a": Biomarker("a", mean25=10.0, sd=2.0, slope=0.2),
    "b": Biomarker("b", mean25=5.0, sd=1.0, slope=-0.05),
}


class KDMTests(unittest.TestCase):
    def test_linear_matches_closed_form(self):
        m = KDM(LINEAR, prior_sd=None)
        x = [19.0, 3.0]
        num = den = 0.0
        for b, v in zip(LINEAR.values(), x):
            q = b.mean25 - 25 * b.slope
            num += (v - q) * b.slope / b.sd ** 2
            den += (b.slope / b.sd) ** 2
        e = m.predict([x], ["a", "b"])[0]
        self.assertAlmostEqual(e.age, num / den, places=2)
        self.assertAlmostEqual(e.se, 1 / math.sqrt(den), places=2)

    def test_on_curve_recovers_age(self):
        m = KDM.from_config()
        names = list(m.biomarkers)
        for age in (30, 55, 75):
            row = [m.biomarkers[n].expected(age) for n in names]
            self.assertAlmostEqual(m.predict([row], names)[0].age, age, delta=0.05)

    def test_older_values_look_older(self):
        m = KDM.from_config()
        names = list(m.biomarkers)
        young = [m.biomarkers[n].expected(30) for n in names]
        old = [m.biomarkers[n].expected(70) for n in names]
        a, b = m.predict_ages([young, old], names)
        self.assertLess(a, b)

    def test_missing_and_unknown_columns(self):
        m = KDM(LINEAR, prior_sd=None)
        out = m.predict([[19.0, float("nan"), 1], [None, None, 2]], ["a", "b", "extra"])
        self.assertEqual(out[0].n, 1)
        self.assertAlmostEqual(out[0].age, 70.0, places=2)
        self.assertIsNone(out[1])

    def test_prior_pulls_toward_chronological(self):
        m = KDM(LINEAR, prior_sd=9.0)
        row = [LINEAR["a"].expected(70), LINEAR["b"].expected(70)]
        ba_e = m.predict([row], ["a", "b"])[0]
        ba_ec = m.predict([row], ["a", "b"], chronological_age=[40])[0]
        self.assertLess(ba_ec.age, ba_e.age)
        self.assertGreater(ba_ec.age, 40)
        self.assertLess(ba_ec.se, ba_e.se)

    def test_fit_recovers_linear_parameters(self):
        rng = random.Random(1)
        ages = [rng.uniform(20, 80) for _ in range(400)]
        X = [[b.expected(a) + rng.gauss(0, b.sd) for b in LINEAR.values()] for a in ages]
        p = fit(X, list(LINEAR), ages)
        self.assertAlmostEqual(p["a"]["slope"], 0.2, delta=0.02)
        self.assertAlmostEqual(p["b"]["sd"], 1.0, delta=0.1)

    def test_config_entries_cite_a_source(self):
        cfg = json.loads(DEFAULT_PARAMS.read_text())
        for name, p in cfg["biomarkers"].items():
            self.assertTrue(p.get("source"), name)


if __name__ == "__main__":
    unittest.main()
