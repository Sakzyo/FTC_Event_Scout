import base64
import csv
import json
import os
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request

from score_breakdown import build_score_breakdown_rows, score_totals

BASE_URL = "https://ftc-api.firstinspires.org"
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


def make_request(path, season, params=None):
    url = f"{BASE_URL}/v2.0/{int(season)}/{path}"
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(
        url,
        headers={**_authorization_headers(), "Accept": "application/json"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            raise RuntimeError(
                "FIRST Events rejected the saved credentials (401 Unauthorized). "
                "Open Settings and verify the API username and token."
            ) from exc
        raise RuntimeError(
            f"FIRST Events request failed with HTTP {exc.code}: {exc.reason}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Could not reach FIRST Events: {exc.reason}") from exc


def load_matches(event_code, season):
    matches = []
    for tournament_level in TOURNAMENT_LEVELS:
        response = make_request(
            f"matches/{event_code}",
            season,
            params={"tournamentLevel": tournament_level},
        )
        matches.extend(response.get("matches", []))
    return matches


def load_score_lookup(event_code, season):
    score_lookup = {}
    for tournament_level in TOURNAMENT_LEVELS:
        response = make_request(f"scores/{event_code}/{tournament_level}", season)
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


def flatten_match(match, score_lookup, season):
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

    red_final = match.get("scoreRedFinal")
    blue_final = match.get("scoreBlueFinal")
    red_foul_score = match.get("scoreRedFoul")
    blue_foul_score = match.get("scoreBlueFoul")
    red_totals = score_totals(
        season,
        red_score,
        match_auto=match.get("scoreRedAuto"),
        match_final=red_final,
        match_foul=red_foul_score,
    )
    blue_totals = score_totals(
        season,
        blue_score,
        match_auto=match.get("scoreBlueAuto"),
        match_final=blue_final,
        match_foul=blue_foul_score,
    )

    if red_totals["teleop"] is None and red_final is not None and red_totals["auto"] is not None:
        red_totals["teleop"] = red_final - red_totals["auto"] - (red_foul_score or 0)
    if blue_totals["teleop"] is None and blue_final is not None and blue_totals["auto"] is not None:
        blue_totals["teleop"] = blue_final - blue_totals["auto"] - (blue_foul_score or 0)

    red_breakdown = build_score_breakdown_rows(
        season,
        red_score,
        blue_score,
        match_auto=match.get("scoreRedAuto"),
        match_final=red_final,
        match_foul=red_foul_score,
    )
    blue_breakdown = build_score_breakdown_rows(
        season,
        blue_score,
        red_score,
        match_auto=match.get("scoreBlueAuto"),
        match_final=blue_final,
        match_foul=blue_foul_score,
    )

    return {
        "Series": match.get("series"),
        "Match Number": match.get("matchNumber"),
        "Red1 Team Number": teams_by_station.get("Red1"),
        "Red2 Team Number": teams_by_station.get("Red2"),
        "Blue1 Team Number": teams_by_station.get("Blue1"),
        "Blue2 Team Number": teams_by_station.get("Blue2"),
        "Red Auto Score": red_totals["auto"],
        "Red Auto Artifact Points": red_score.get("autoArtifactPoints"),
        "Red Auto Classified Artifacts": red_score.get("autoClassifiedArtifacts"),
        "Red Auto Overflow Artifacts": red_score.get("autoOverflowArtifacts"),
        "Red Auto Pattern Points": red_score.get("autoPatternPoints"),
        "Red Auto Leave Points": red_score.get("autoLeavePoints"),
        "Red Teleop Score": red_totals["teleop"],
        "Red Teleop Artifact Points": red_score.get("teleopArtifactPoints"),
        "Red Teleop Classified Artifacts": red_score.get("teleopClassifiedArtifacts"),
        "Red Teleop Overflow Artifacts": red_score.get("teleopOverflowArtifacts"),
        "Red Teleop Pattern Points": red_score.get("teleopPatternPoints"),
        "Red Teleop Depot Points": red_score.get("teleopDepotPoints"),
        "Red Endgame Score": red_totals["endgame"],
        "Red Foul Score": red_foul_score,
        "Red Foul Committed": red_totals["foul_committed"],
        "Red Major Fouls": red_totals["major_fouls"],
        "Red Minor Fouls": red_totals["minor_fouls"],
        "Red Final Score": red_final,
        "Red Score Breakdown": json.dumps(red_breakdown, ensure_ascii=False, separators=(",", ":")),
        "Blue Auto Score": blue_totals["auto"],
        "Blue Auto Artifact Points": blue_score.get("autoArtifactPoints"),
        "Blue Auto Classified Artifacts": blue_score.get("autoClassifiedArtifacts"),
        "Blue Auto Overflow Artifacts": blue_score.get("autoOverflowArtifacts"),
        "Blue Auto Pattern Points": blue_score.get("autoPatternPoints"),
        "Blue Auto Leave Points": blue_score.get("autoLeavePoints"),
        "Blue Teleop Score": blue_totals["teleop"],
        "Blue Teleop Artifact Points": blue_score.get("teleopArtifactPoints"),
        "Blue Teleop Classified Artifacts": blue_score.get("teleopClassifiedArtifacts"),
        "Blue Teleop Overflow Artifacts": blue_score.get("teleopOverflowArtifacts"),
        "Blue Teleop Pattern Points": blue_score.get("teleopPatternPoints"),
        "Blue Teleop Depot Points": blue_score.get("teleopDepotPoints"),
        "Blue Endgame Score": blue_totals["endgame"],
        "Blue Foul Score": blue_foul_score,
        "Blue Foul Committed": blue_totals["foul_committed"],
        "Blue Major Fouls": blue_totals["major_fouls"],
        "Blue Minor Fouls": blue_totals["minor_fouls"],
        "Blue Final Score": blue_final,
        "Blue Score Breakdown": json.dumps(blue_breakdown, ensure_ascii=False, separators=(",", ":")),
    }


def generate_event_match_details_csv(event_code, season, output_dir=OUTPUT_DIR):
    safe_event = event_code.strip().upper()
    if not safe_event:
        raise RuntimeError("Event code is required.")

    matches = load_matches(safe_event, season)
    score_lookup = load_score_lookup(safe_event, season)

    if not matches:
        raise RuntimeError(f"No matches found for event code {safe_event}.")

    rows = [flatten_match(match, score_lookup, season) for match in matches]

    rows.sort(
        key=lambda row: (
            row["Series"] if row["Series"] is not None else -1,
            row["Match Number"] if row["Match Number"] is not None else -1,
            row["Red1 Team Number"] if row["Red1 Team Number"] is not None else -1,
        )
    )

    season_output_dir = os.path.join(output_dir, str(int(season)))
    os.makedirs(season_output_dir, exist_ok=True)
    filename = os.path.join(season_output_dir, f"{safe_event} Match Details.csv")

    with open(filename, mode='w', newline='', encoding='utf-8-sig') as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    return filename


if __name__ == "__main__":
    event = input("Enter the event code: ").upper()
    selected_season = int(input("Enter the season start year [2025]: ") or "2025")
    output_file = generate_event_match_details_csv(event, selected_season)
    print(f"\nSaving match data to {output_file}...")
    print("Done!\n")
