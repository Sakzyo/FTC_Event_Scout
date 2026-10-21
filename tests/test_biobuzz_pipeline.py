"""BIOBUZZ export regressions for incomplete FIRST score details."""

import json
import unittest
from unittest.mock import patch

from scrape import flatten_match, load_score_lookup


class BioBuzzPipelineTests(unittest.TestCase):
    def match(self):
        return {
            "tournamentLevel": "qual",
            "series": 1,
            "matchNumber": 1,
            "scoreRedAuto": 30,
            "scoreBlueAuto": 20,
            "scoreRedFinal": 100,
            "scoreBlueFinal": 95,
            "scoreRedFoul": 15,
            "scoreBlueFoul": 5,
            "teams": [
                {"station": "Red1", "teamNumber": 1},
                {"station": "Red2", "teamNumber": 2},
                {"station": "Blue1", "teamNumber": 3},
                {"station": "Blue2", "teamNumber": 4},
            ],
        }

    def test_unavailable_details_preserve_derived_teleop_in_display(self):
        row = flatten_match(self.match(), {}, 2026)
        red = {item["id"]: item["value"] for item in json.loads(row["Red Score Breakdown"])}
        blue = {item["id"]: item["value"] for item in json.loads(row["Blue Score Breakdown"])}

        self.assertEqual(row["Red Teleop Score"], 65)
        self.assertEqual(row["Blue Teleop Score"], 60)
        self.assertEqual(red.get("teleop"), "65")
        self.assertEqual(blue.get("teleop"), "60")

    def test_unknown_fouls_do_not_fabricate_a_teleop_total(self):
        match = self.match()
        match["scoreRedFoul"] = None
        match["scoreBlueFoul"] = None

        row = flatten_match(match, {}, 2026)

        self.assertIsNone(row["Red Teleop Score"])
        self.assertIsNone(row["Blue Teleop Score"])

    def test_legacy_missing_detail_display_does_not_gain_biobuzz_fallback(self):
        for season in range(2019, 2026):
            with self.subTest(season=season):
                row = flatten_match(self.match(), {}, season)
                details = json.loads(row["Red Score Breakdown"])
                values = {item["id"]: item["value"] for item in details}
                self.assertEqual(row["Red Teleop Score"], 65)
                self.assertNotIn("teleop", values)

    def test_nullable_alliances_keep_the_match_without_detail(self):
        response = {
            "matchScores": [{
                "matchLevel": "qual",
                "matchSeries": 1,
                "matchNumber": 1,
                "alliances": None,
            }],
        }
        with patch("scrape.make_request", return_value=response):
            lookup = load_score_lookup("TEST", 2026)

        self.assertEqual(lookup, {("qual", 1, 1): {}})

    def test_nullable_score_list_is_an_unavailable_breakdown(self):
        with patch("scrape.make_request", return_value={"matchScores": None}):
            lookup = load_score_lookup("TEST", 2026)

        self.assertEqual(lookup, {})


if __name__ == "__main__":
    unittest.main()
