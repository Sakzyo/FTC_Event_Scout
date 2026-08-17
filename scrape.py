import base64
import csv
import os
from pathlib import Path

import requests

BASE_URL = "https://ftc-api.firstinspires.org"
SEASON = "2025"
OUTPUT_DIR = "event_results"
TOURNAMENT_LEVELS = ("qual", "playoff")


def _credentials_from_file(path):
    """Read the two supported dotenv keys without requiring python-dotenv."""
    values = {}
    credentials_path = Path(path).expanduser()
    if not credentials_path.is_file():
        return values

    for raw_line in credentials_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        values[key.strip()] = value
    return values


def _authorization_headers():
    credentials_path = os.getenv("FTC_SCOUT_CREDENTIALS_FILE", "credentials.env")
    file_values = _credentials_from_file(credentials_path)
    username = os.getenv("USERNAME") or file_values.get("USERNAME")
    token = os.getenv("TOKEN") or file_values.get("TOKEN")

    if not username or not token:
        raise RuntimeError(
            "FIRST API credentials are missing. Open FTC Event Scout Settings and "
            "enter your FIRST API username and token."
        )

    encoded = base64.b64encode(f"{username}:{token}".encode()).decode()
    return {"Authorization": f"Basic {encoded}"}


def make_request(path, params=None):
    response = requests.get(
        f"{BASE_URL}/v2.0/{SEASON}/{path}",
        headers=_authorization_headers(),
        params=params,
        timeout=30,
    )
    response.raise_for_status()
    return response.json()


def load_matches(event_code):
    matches = []
    for tournament_level in TOURNAMENT_LEVELS:
        response = make_request(f"matches/{event_code}", params={"tournamentLevel": tournament_level})
        matches.extend(response.get("matches", []))
    return matches


def load_score_lookup(event_code):
    score_lookup = {}
    for tournament_level in TOURNAMENT_LEVELS:
        response = make_request(f"scores/{event_code}/{tournament_level}")
        for match_score in response.get("matchScores", []):
            key = (
                match_score.get("matchLevel"),
                match_score.get("matchSeries"),
                match_score.get("matchNumber"),
            )
            alliances = {
                alliance.get("alliance"): alliance for alliance in match_score.get("alliances", [])
            }
            score_lookup[key] = alliances
    return score_lookup


def flatten_match(match, score_lookup):
    teams_by_station = {
        team.get("station", ""): team.get("teamNumber")
        for team in match.get("teams", [])
        if team.get("onField", True)
    }

    score_key = (
        match.get("tournamentLevel"),
        match.get("series"),
        match.get("matchNumber"),
    )
    alliance_scores = score_lookup.get(score_key, {})
    red_score = alliance_scores.get("Red", {})
    blue_score = alliance_scores.get("Blue", {})

    return {
        "Series": match.get("series"),
        "Match Number": match.get("matchNumber"),
        "Red1 Team Number": teams_by_station.get("Red1"),
        "Red2 Team Number": teams_by_station.get("Red2"),
        "Blue1 Team Number": teams_by_station.get("Blue1"),
        "Blue2 Team Number": teams_by_station.get("Blue2"),
        "Red Auto Score": red_score.get("autoPoints", match.get("scoreRedAuto")),
        "Red Auto Artifact Points": red_score.get("autoArtifactPoints"),
        "Red Auto Classified Artifacts": red_score.get("autoClassifiedArtifacts"),
        "Red Auto Overflow Artifacts": red_score.get("autoOverflowArtifacts"),
        "Red Auto Pattern Points": red_score.get("autoPatternPoints"),
        "Red Auto Leave Points": red_score.get("autoLeavePoints"),
        "Red Teleop Score": red_score.get("teleopPoints"),
        "Red Teleop Artifact Points": red_score.get("teleopArtifactPoints"),
        "Red Teleop Classified Artifacts": red_score.get("teleopClassifiedArtifacts"),
        "Red Teleop Overflow Artifacts": red_score.get("teleopOverflowArtifacts"),
        "Red Teleop Pattern Points": red_score.get("teleopPatternPoints"),
        "Red Teleop Depot Points": red_score.get("teleopDepotPoints"),
        "Red Endgame Score": red_score.get("teleopBasePoints"),
        "Red Foul Committed": red_score.get("foulPointsCommitted", match.get("scoreRedFoul")),
        "Red Major Fouls": red_score.get("majorFouls"),
        "Red Minor Fouls": red_score.get("minorFouls"),
        "Red Final Score": match.get("scoreRedFinal"),
        "Blue Auto Score": blue_score.get("autoPoints", match.get("scoreBlueAuto")),
        "Blue Auto Artifact Points": blue_score.get("autoArtifactPoints"),
        "Blue Auto Classified Artifacts": blue_score.get("autoClassifiedArtifacts"),
        "Blue Auto Overflow Artifacts": blue_score.get("autoOverflowArtifacts"),
        "Blue Auto Pattern Points": blue_score.get("autoPatternPoints"),
        "Blue Auto Leave Points": blue_score.get("autoLeavePoints"),
        "Blue Teleop Score": blue_score.get("teleopPoints"),
        "Blue Teleop Artifact Points": blue_score.get("teleopArtifactPoints"),
        "Blue Teleop Classified Artifacts": blue_score.get("teleopClassifiedArtifacts"),
        "Blue Teleop Overflow Artifacts": blue_score.get("teleopOverflowArtifacts"),
        "Blue Teleop Pattern Points": blue_score.get("teleopPatternPoints"),
        "Blue Teleop Depot Points": blue_score.get("teleopDepotPoints"),
        "Blue Endgame Score": blue_score.get("teleopBasePoints"),
        "Blue Foul Committed": blue_score.get("foulPointsCommitted", match.get("scoreBlueFoul")),
        "Blue Major Fouls": blue_score.get("majorFouls"),
        "Blue Minor Fouls": blue_score.get("minorFouls"),
        "Blue Final Score": match.get("scoreBlueFinal"),
    }


def generate_event_match_details_csv(event_code, output_dir=OUTPUT_DIR):
    safe_event = event_code.strip().upper()
    if not safe_event:
        raise RuntimeError("Event code is required.")

    matches = load_matches(safe_event)
    score_lookup = load_score_lookup(safe_event)

    if not matches:
        raise RuntimeError(f"No matches found for event code {safe_event}.")

    rows = [flatten_match(match, score_lookup) for match in matches]

    rows.sort(
        key=lambda row: (
            row["Series"] if row["Series"] is not None else -1,
            row["Match Number"] if row["Match Number"] is not None else -1,
            row["Red1 Team Number"] if row["Red1 Team Number"] is not None else -1,
        )
    )

    os.makedirs(output_dir, exist_ok=True)
    filename = os.path.join(output_dir, f"{safe_event} Match Details.csv")

    with open(filename, mode='w', newline='', encoding='utf-8-sig') as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    return filename


if __name__ == "__main__":
    event = input("Enter the event code: ").upper()
    output_file = generate_event_match_details_csv(event)
    print(f"\nSaving match data to {output_file}...")
    print("Done!\n")
