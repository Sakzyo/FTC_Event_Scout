import json
import unittest

from scrape import flatten_match
from score_breakdown import build_score_breakdown_rows, score_totals


BIOBUZZ_SCORE = {
    "autoHiveTips": 2,
    "autoRobot1Leave": True,
    "autoRobot2Leave": False,
    "autoRobot1Park": False,
    "autoRobot2Park": True,
    "autoLeavePoints": 3,
    "autoParkPoints": 4,
    "autoHivePoints": 10,
    "teleopHiveTips": 3,
    "teleopHivePollenNectar": 8,
    "redAllianceFlower": ["RED_NECTAR", "POLLEN", "BLUE_NECTAR"],
    "scoringFlower": ["POLLEN", "BLUE_NECTAR"],
    "blueAllianceFlower": ["BLUE_NECTAR", "RED_NECTAR"],
    "audienceFlower": [],
    "teleopGardenPollenNectar": 6,
    "teleopRobot1Park": True,
    "teleopRobot2Park": False,
    "teleopHivePoints": 45,
    "teleopFlowerPoints": 32,
    "teleopGardenPoints": 6,
    "teleopParkPoints": 12,
    "autoPoints": 20,
    "teleopPoints": 100,
    "foulPointsCommitted": 5,
    "preFoulTotal": 120,
    "swarmRP": True,
    "pollinator1RP": False,
    "pollinator2RP": True,
    "totalPoints": 130,
    "majorFouls": 0,
    "minorFouls": 1,
    "alliance": "Red",
    "team": 1,
}


class BiobuzzScoreBreakdownTests(unittest.TestCase):
    def test_biobuzz_exposes_official_auto_and_teleop_details(self):
        rows = build_score_breakdown_rows(2026, BIOBUZZ_SCORE, {})
        values = {row["id"]: row["value"] for row in rows}
        expected = {
            "auto": "20",
            "auto-hive-tips": "2",
            "auto-leave": "Yes · No",
            "auto-park": "No · Yes",
            "auto-leave-points": "3",
            "auto-park-points": "4",
            "auto-hive-points": "10",
            "teleop": "100",
            "teleop-hive-tips": "3",
            "teleop-hive-pollen-nectar": "8",
            "teleop-garden-pollen-nectar": "6",
            "teleop-park": "Yes · No",
            "teleop-hive-points": "45",
            "teleop-flower-points": "32",
            "teleop-garden-points": "6",
            "teleop-park-points": "12",
        }
        self.assertEqual({key: values.get(key) for key in expected}, expected)
        self.assertNotIn("auto-classifier", values)
        self.assertNotIn("teleop-classifier", values)

    def test_flower_contents_keep_api_order_with_readable_full_tokens(self):
        rows = build_score_breakdown_rows(2026, BIOBUZZ_SCORE, {})
        values = {row["id"]: row["value"] for row in rows}
        self.assertEqual(values.get("teleop-flower-red"), "Red Nectar / Pollen / Blue Nectar")
        self.assertEqual(values.get("teleop-flower-scoring"), "Pollen / Blue Nectar")
        self.assertEqual(values.get("teleop-flower-blue"), "Blue Nectar / Red Nectar")
        self.assertEqual(values.get("teleop-flower-audience"), "Empty")

    def test_missing_details_have_same_row_schema_as_reported_details(self):
        red = build_score_breakdown_rows(2026, {}, {})
        blue = build_score_breakdown_rows(2026, BIOBUZZ_SCORE, BIOBUZZ_SCORE)
        schema = lambda rows: [(row["id"], row["label"], row["indent"], row["emphasized"]) for row in rows]
        self.assertEqual(schema(red), schema(blue))
        self.assertEqual(len(red), 27)
        self.assertTrue(all(row["value"] == "—" for row in red))
        self.assertTrue(all(set(row) == {"id", "label", "value", "indent", "emphasized"} for row in blue))

    def test_unknown_empty_zero_and_false_remain_distinct(self):
        rows = build_score_breakdown_rows(
            2026,
            {
                "autoHiveTips": 0,
                "autoRobot1Leave": False,
                "autoRobot2Leave": None,
                "redAllianceFlower": None,
                "scoringFlower": [],
                "swarmRP": False,
                "pollinator1RP": None,
            },
            {},
        )
        values = {row["id"]: row["value"] for row in rows}
        self.assertEqual(values.get("auto-hive-tips"), "0")
        self.assertEqual(values.get("auto-leave"), "No · —")
        self.assertEqual(values.get("teleop-flower-red"), "—")
        self.assertEqual(values.get("teleop-flower-scoring"), "Empty")
        self.assertEqual(values.get("teleop-flower-blue"), "—")
        self.assertEqual(values.get("rp-swarm"), "No")
        self.assertEqual(values.get("rp-pollinator-1"), "—")
        self.assertEqual(values.get("rp-pollinator-2"), "—")

    def test_official_final_precedes_three_separate_reported_rp_values(self):
        rows = build_score_breakdown_rows(
            2026,
            BIOBUZZ_SCORE,
            {"minorFouls": 2, "majorFouls": 1},
            match_auto=99,
            match_final=135,
            match_foul_awarded=15,
        )
        self.assertEqual(
            [(row["id"], row["value"]) for row in rows[-7:]],
            [("penalty", "15"), ("penalty-minor", "2"), ("penalty-major", "1"),
             ("final", "135"), ("rp-swarm", "Yes"), ("rp-pollinator-1", "No"),
             ("rp-pollinator-2", "Yes")],
        )
        self.assertTrue(all(not row["emphasized"] for row in rows[-3:]))

    def test_teleop_keeps_parking_in_total_and_exposes_parking_as_endgame(self):
        totals = score_totals(2026, BIOBUZZ_SCORE, match_auto=99, match_final=135)
        self.assertEqual(totals["auto"], 20)
        self.assertEqual(totals["teleop"], 100)
        self.assertEqual(totals["endgame"], 12)
        self.assertEqual(totals["final"], 135)

    def test_missing_totals_are_not_inferred_from_components_or_total_points(self):
        score = dict(BIOBUZZ_SCORE, autoPoints=None, teleopPoints=None, teleopParkPoints=None)
        totals = score_totals(2026, score)
        self.assertIsNone(totals["auto"])
        self.assertIsNone(totals["teleop"])
        self.assertIsNone(totals["endgame"])
        self.assertIsNone(totals["final"])
        rows = build_score_breakdown_rows(2026, score, {})
        values = {row["id"]: row["value"] for row in rows}
        self.assertEqual(values.get("auto"), "—")
        self.assertEqual(values.get("teleop"), "—")
        self.assertEqual(values.get("final"), "—")

    def test_match_teleop_fallback_keeps_unreported_categories_unknown(self):
        rows = build_score_breakdown_rows(
            2026, {}, {}, match_auto=30, match_final=100,
            match_foul_awarded=5, match_teleop=65,
        )
        values = {row["id"]: row["value"] for row in rows}
        self.assertEqual(values.get("teleop"), "65")
        self.assertEqual(values.get("auto"), "30")
        self.assertEqual(values.get("teleop-hive-points"), "—")
        self.assertEqual(values.get("teleop-park-points"), "—")
        self.assertEqual(values.get("rp-swarm"), "—")
        reported = build_score_breakdown_rows(
            2026, BIOBUZZ_SCORE, {}, match_teleop=65,
        )
        self.assertEqual(next(row["value"] for row in reported if row["id"] == "teleop"), "100")


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
            match_foul_awarded=35,
        )
        values = {row["id"]: row["value"] for row in rows}
        self.assertEqual(values["penalty"], "35")
        self.assertEqual(values["penalty-minor"], "1")
        self.assertEqual(values["penalty-major"], "2")

    def test_match_export_awards_each_alliance_the_opponents_committed_fouls(self):
        match = {
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
                    "foulPointsCommitted": 15,
                    "minorFouls": 1,
                    "majorFouls": 1,
                },
                "Blue": {
                    "autoPoints": 20,
                    "teleopPoints": 60,
                    "foulPointsCommitted": 5,
                    "minorFouls": 1,
                    "majorFouls": 0,
                },
            }
        }

        row = flatten_match(match, score_lookup, 2024)
        red_rows = {
            item["id"]: item["value"]
            for item in json.loads(row["Red Score Breakdown"])
        }
        blue_rows = {
            item["id"]: item["value"]
            for item in json.loads(row["Blue Score Breakdown"])
        }

        self.assertEqual(row["Red Foul Score"], 5)
        self.assertEqual(row["Blue Foul Score"], 15)
        self.assertEqual(row["Red Foul Committed"], 15)
        self.assertEqual(row["Blue Foul Committed"], 5)
        self.assertEqual(red_rows["penalty"], "5")
        self.assertEqual(blue_rows["penalty"], "15")

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
