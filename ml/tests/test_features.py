import json
import pathlib
import unittest

from sha_biomarkers import extract, functional_age
from sha_biomarkers.synth import make_session

EXAMPLE = pathlib.Path(__file__).parents[2] / "packages/schema/examples/session.example.json"


class FeatureTests(unittest.TestCase):
    def test_example_session(self):
        f = extract(json.loads(EXAMPLE.read_text()))
        self.assertAlmostEqual(f["simple_rt_median"], 0.3)
        self.assertEqual(f["corsi_span"], 3)
        self.assertEqual(f["commission_rate"], 0.5)

    def test_older_synthetic_is_slower(self):
        young = extract(make_session(25, 1))
        old = extract(make_session(75, 1))
        self.assertGreater(old["simple_rt_median"], young["simple_rt_median"])
        self.assertGreater(functional_age(old), functional_age(young))

    def test_familiarization_ignored(self):
        s = make_session(40, 2)
        for b in s["blocks"]:
            if b["familiarization"]:
                for t in b["trials"]:
                    t["move_t"] = t["spawn_t"] + 9
        self.assertLess(extract(s)["simple_rt_median"], 1.0)


if __name__ == "__main__":
    unittest.main()
