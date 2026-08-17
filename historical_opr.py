"""Fetch historical OPR data from the ftcscout.org GraphQL API.

Used as a fallback for events that have not started yet (no matches played),
to give the user an at-a-glance preview of the highest OPR each registered
team has historically achieved across past seasons.
"""

import json
import urllib.request
import urllib.error


FTCSCOUT_GRAPHQL_URL = "https://api.ftcscout.org/graphql"
DEFAULT_SEASON = 2025
# Seasons to query for "highest OPR ever achieved". Ordered newest first so
# that ties (extremely unlikely with floats) prefer the most recent season.
HISTORICAL_SEASONS = [2025, 2024, 2023, 2022, 2021, 2020, 2019]


def _build_quickstats_alias_block():
    return "\n".join(
        f"            s{season}: quickStats(season: {season}) {{ "
        f"tot {{ value rank }} auto {{ value }} dc {{ value }} }}"
        for season in HISTORICAL_SEASONS
    )


def _build_event_query(event_code, season):
    quickstats_block = _build_quickstats_alias_block()
    return (
        "query {\n"
        f'  event: eventByCode(season: {int(season)}, code: "{event_code}") {{\n'
        "    code\n"
        "    name\n"
        "    started\n"
        "    ongoing\n"
        "    finished\n"
        "    hasMatches\n"
        "    teams {\n"
        "      teamNumber\n"
        "      team {\n"
        "        number\n"
        "        name\n"
        "        rookieYear\n"
        f"{quickstats_block}\n"
        "      }\n"
        "    }\n"
        "  }\n"
        "}\n"
    )


def _post_graphql(query, timeout=20):
    body = json.dumps({"query": query}).encode("utf-8")
    req = urllib.request.Request(
        FTCSCOUT_GRAPHQL_URL,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "IA_OPR_Calc/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise RuntimeError(
            f"ftcscout.org GraphQL request failed with HTTP {exc.code}: {exc.reason}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(
            f"Could not reach ftcscout.org GraphQL API: {exc.reason}"
        ) from exc

    if payload.get("errors"):
        # Surface the first GraphQL error message verbatim.
        first = payload["errors"][0]
        raise RuntimeError(
            f"ftcscout.org GraphQL error: {first.get('message', 'unknown error')}"
        )
    return payload.get("data") or {}


def _team_summary(team_entry):
    team = team_entry.get("team") or {}
    number = team.get("number") or team_entry.get("teamNumber")
    name = team.get("name") or ""
    rookie_year = team.get("rookieYear")

    per_season = {}
    highest_value = None
    highest_season = None
    highest_rank = None
    for season in HISTORICAL_SEASONS:
        block = team.get(f"s{season}")
        if not block:
            continue
        tot = block.get("tot") or {}
        value = tot.get("value")
        if value is None:
            continue
        per_season[str(season)] = {
            "tot": value,
            "rank": tot.get("rank"),
            "auto": (block.get("auto") or {}).get("value"),
            "dc": (block.get("dc") or {}).get("value"),
        }
        if highest_value is None or value > highest_value:
            highest_value = value
            highest_season = season
            highest_rank = tot.get("rank")

    return {
        "teamNumber": number,
        "teamName": name,
        "rookieYear": rookie_year,
        "highestOpr": highest_value,
        "highestOprSeason": highest_season,
        "highestOprRank": highest_rank,
        "perSeason": per_season,
    }


def fetch_event_preview(event_code, season=DEFAULT_SEASON):
    """Return a dict describing an event's registered teams and historical OPR.

    Shape:
        {
            "eventCode": str,
            "eventName": str,
            "started": bool,
            "ongoing": bool,
            "finished": bool,
            "hasMatches": bool,
            "season": int,
            "teams": [
                {
                    "teamNumber": int,
                    "teamName": str,
                    "rookieYear": int | None,
                    "highestOpr": float | None,
                    "highestOprSeason": int | None,
                    "highestOprRank": int | None,
                    "perSeason": { "2025": {...}, ... },
                },
                ...
            ],
        }
    """
    safe_event = str(event_code).strip().upper()
    if not safe_event:
        raise ValueError("event_code is required.")

    data = _post_graphql(_build_event_query(safe_event, season))
    event = data.get("event")
    if not event:
        raise RuntimeError(
            f"Event '{safe_event}' was not found on ftcscout.org for season {season}."
        )

    team_entries = event.get("teams") or []
    teams = [_team_summary(entry) for entry in team_entries]
    teams.sort(
        key=lambda t: (t["highestOpr"] is None, -(t["highestOpr"] or 0.0))
    )

    return {
        "eventCode": event.get("code") or safe_event,
        "eventName": event.get("name") or "",
        "started": bool(event.get("started")),
        "ongoing": bool(event.get("ongoing")),
        "finished": bool(event.get("finished")),
        "hasMatches": bool(event.get("hasMatches")),
        "season": int(season),
        "teams": teams,
    }


if __name__ == "__main__":
    import sys

    code = sys.argv[1] if len(sys.argv) > 1 else "AEDUS"
    print(json.dumps(fetch_event_preview(code), indent=2))
