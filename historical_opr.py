"""Fetch season OPR data from the ftcscout.org GraphQL API.

Used as a fallback for events that have not started yet (no matches played),
to give the user an at-a-glance preview of the OPR each registered team has
achieved so far in the event's own season.
"""

import json
import urllib.request
import urllib.error


FTCSCOUT_GRAPHQL_URL = "https://api.ftcscout.org/graphql"
DEFAULT_SEASON = 2025


def _build_event_query(event_code, season):
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
        f"        quickStats(season: {int(season)}) {{ tot {{ value }} }}\n"
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
    quick_stats = team.get("quickStats") or {}
    return {
        "teamNumber": team.get("number") or team_entry.get("teamNumber"),
        "teamName": team.get("name") or "",
        "rookieYear": team.get("rookieYear"),
        "seasonOpr": (quick_stats.get("tot") or {}).get("value"),
    }


def fetch_event_preview(event_code, season=DEFAULT_SEASON):
    """Return a dict describing an event's registered teams and their OPR in its season.

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
                    "seasonOpr": float | None,
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
        key=lambda t: (t["seasonOpr"] is None, -(t["seasonOpr"] or 0.0))
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
