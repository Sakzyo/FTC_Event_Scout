import json
import unittest

from scrape import flatten_match
from score_breakdown import build_score_breakdown_rows, score_totals


class ScoreBreakdownTests(unittest.TestCase):
    def test_each_published_season_uses_its_own_sections(self):
        fixtures = {
            2019: (
                {"autonomousPoints": 30, "driverControlledPoints": 17, "endGamePoints": 15},
                ["Autonomous", "Driver Controlled", "End Game"],
            ),
            2020: (
                {"autoPoints": 73, "dcPoints": 104, "endgamePoints": 40},
                ["Autonomous", "Driver Controlled", "End Game"],
            ),
            2021: (
                {"autoPoints": 42, "driverControlledPoints": 72, "endgamePoints": 101},
                ["Autonomous", "Driver Controlled", "End Game"],
            ),
            2022: (
                {"autoPoints": 48, "dcPoints": 66, "endgamePoints": 44},
                ["Auto", "Driver Controlled", "End Game"],
            ),
            2023: (
                {"autoPoints": 5, "dcPoints": 19, "endgamePoints": 25},
                ["Auto", "Driver Controlled", "End Game"],
            ),
            2024: (
                {"autoPoints": 58, "teleopPoints": 114, "endGamePoints": 30},
                ["Total Auto", "Total Teleop"],
            ),
            2025: (
                {"autoPoints": 49, "teleopPoints": 87, "teleopBasePoints": 15},
                ["Auto", "Teleop"],
            ),
        }

        for season, (score, expected) in fixtures.items():
            with self.subTest(season=season):
                rows = build_score_breakdown_rows(season, score, {}, match_final=100)
                section_labels = [row["label"] for row in rows if row["emphasized"]]
                self.assertEqual(section_labels[:-1], expected)
                self.assertEqual(section_labels[-1], "Final Score")

    def test_each_published_season_exposes_game_specific_rows(self):
        fixtures = {
            2019: ({"autoStones": 2}, "Auto Stones"),
            2020: ({"autoPowerShotPoints": 30}, "Power Shot Points"),
            2021: ({"carouselPoints": 10}, "Carousel Points"),
            2022: ({"ownedJunctions": 4}, "Owned Junctions"),
            2023: ({"mosaics": 2}, "Mosaics"),
            2024: ({"autoSamplePoints": 12}, "Sample Points"),
            2025: ({"teleopDepotPoints": 6}, "Depot Points"),
        }

        for season, (score, expected_label) in fixtures.items():
            with self.subTest(season=season):
                labels = {
                    row["label"]
                    for row in build_score_breakdown_rows(season, score, {})
                }
                self.assertIn(expected_label, labels)

    def test_pre_2024_teleop_total_includes_endgame(self):
        totals = score_totals(
            2023,
            {"autoPoints": 5, "dcPoints": 19, "endgamePoints": 25},
        )
        self.assertEqual(totals["teleop"], 44)

    def test_2024_teleop_total_is_not_double_counted(self):
        totals = score_totals(
            2024,
            {"autoPoints": 58, "teleopPoints": 114, "endGamePoints": 30},
        )
        self.assertEqual(totals["teleop"], 114)
        self.assertEqual(totals["endgame"], 30)

    def test_2025_endgame_uses_base_points(self):
        totals = score_totals(
            2025,
            {"autoPoints": 49, "teleopPoints": 87, "teleopBasePoints": 15},
        )
        self.assertEqual(totals["endgame"], 15)

    def test_decode_classifier_states_use_single_letter_abbreviations(self):
        rows = build_score_breakdown_rows(
            2025,
            {
                "autoClassifierState": ["Green", "Purple", "None"],
                "teleopClassifierState": ["GREEN", "PURPLE", "NONE"],
            },
            {},
        )
        values = {row["id"]: row["value"] for row in rows}
        self.assertEqual(values["auto-classifier"], "G / P / N")
        self.assertEqual(values["teleop-classifier"], "G / P / N")

    def test_penalty_rows_describe_opponent_fouls(self):
        rows = build_score_breakdown_rows(
            2024,
            {"autoPoints": 10, "teleopPoints": 85},
            {"minorFouls": 1, "majorFouls": 2},
            match_final=100,
            match_foul=35,
        )
        values = {row["id"]: row["value"] for row in rows}
        self.assertEqual(values["penalty"], "35")
        self.assertEqual(values["penalty-minor"], "1")
        self.assertEqual(values["penalty-major"], "2")

    def test_match_export_serializes_ordered_season_breakdowns(self):
        match = {
            "tournamentLevel": "qual",
            "series": 1,
            "matchNumber": 1,
            "scoreRedAuto": 30,
            "scoreBlueAuto": 20,
            "scoreRedFinal": 100,
            "scoreBlueFinal": 85,
            "scoreRedFoul": 5,
            "scoreBlueFoul": 0,
            "teams": [
                {"station": "Red1", "teamNumber": 1, "onField": True},
                {"station": "Red2", "teamNumber": 2, "onField": True},
                {"station": "Blue1", "teamNumber": 3, "onField": True},
                {"station": "Blue2", "teamNumber": 4, "onField": True},
            ],
        }
        score_lookup = {
            ("qual", 1, 1): {
                "Red": {
                    "autoPoints": 30,
                    "teleopPoints": 65,
                    "autoSamplePoints": 12,
                    "minorFouls": 0,
                    "majorFouls": 0,
                },
                "Blue": {
                    "autoPoints": 20,
                    "teleopPoints": 65,
                    "teleopSpecimenPoints": 18,
                    "minorFouls": 1,
                    "majorFouls": 0,
                },
            }
        }

        row = flatten_match(match, score_lookup, 2024)
        red_rows = json.loads(row["Red Score Breakdown"])
        blue_rows = json.loads(row["Blue Score Breakdown"])

        self.assertEqual(red_rows[0]["label"], "Total Auto")
        self.assertIn("Sample Points", [item["label"] for item in red_rows])
        self.assertIn("Specimen Points", [item["label"] for item in blue_rows])
        self.assertEqual(row["Red Teleop Score"], 65)


if __name__ == "__main__":
    unittest.main()
