import argparse
import json
import os
from pathlib import Path
import re
import shutil
import socket
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from calculate_opr_from_csv import generate_event_opr_csv
from historical_opr import fetch_event_preview
from scrape import generate_event_match_details_csv


RESOURCE_ROOT = Path(__file__).resolve().parent
EVENT_CODE_PATTERN = re.compile(r"^[A-Z0-9]{2,24}$")
MIN_SEASON = 2019
MAX_SEASON = 2026


def _looks_like_no_matches_error(exc):
    """Return True if the exception indicates the event simply has no matches yet."""
    msg = str(exc).lower()
    return "no matches found" in msg or "no matches for" in msg


class OPRAPIHandler(BaseHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        super().end_headers()

    def do_POST(self):
        if self.path != "/api/generate-opr":
            self._send_json(404, {"error": "Endpoint not found."})
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(content_length).decode("utf-8")
            payload = json.loads(raw_body) if raw_body else {}
            event_code = str(payload.get("eventCode", "")).strip().upper()
            season = payload.get("season")

            if not event_code:
                self._send_json(400, {"error": "eventCode is required."})
                return
            if not EVENT_CODE_PATTERN.fullmatch(event_code):
                self._send_json(
                    400,
                    {"error": "Event codes may contain only 2–24 letters and numbers."},
                )
                return
            if (
                isinstance(season, bool)
                or not isinstance(season, int)
                or not MIN_SEASON <= season <= MAX_SEASON
            ):
                self._send_json(
                    400,
                    {"error": f"season must be an integer from {MIN_SEASON} through {MAX_SEASON}."},
                )
                return

            try:
                match_details_path = generate_event_match_details_csv(event_code, season)
            except Exception as exc:  # noqa: BLE001
                if _looks_like_no_matches_error(exc):
                    # Event has not started yet (no matches played). Fall back
                    # to ftcscout.org for a historical-OPR preview of the
                    # registered teams.
                    try:
                        preview = fetch_event_preview(event_code, season)
                    except Exception as preview_exc:  # noqa: BLE001
                        self._send_json(
                            500,
                            {
                                "error": (
                                    f"No matches yet for {event_code} and the historical "
                                    f"OPR preview could not be loaded: {preview_exc}"
                                )
                            },
                        )
                        return

                    self._send_json(
                        200,
                        {
                            "mode": "preview",
                            "message": (
                                f"{event_code} has no matches in the {season} season. Showing each "
                                f"registered team's highest historical OPR from ftcscout.org."
                            ),
                            "eventCode": preview["eventCode"],
                            "eventName": preview["eventName"],
                            "started": preview["started"],
                            "hasMatches": preview["hasMatches"],
                            "season": preview["season"],
                            "teamCount": len(preview["teams"]),
                            "teams": preview["teams"],
                        },
                    )
                    return

                self._send_json(
                    500,
                    {
                        "error": (
                            f"Unable to refresh match-details CSV for {event_code}: {exc}"
                        )
                    },
                )
                return

            result = generate_event_opr_csv(event_code, season=season)
            if result is None:
                self._send_json(
                    500,
                    {
                        "error": (
                            f"Unable to generate OPR for {event_code} after refreshing match details."
                        )
                    },
                )
                return

            self._send_json(
                200,
                {
                    "message": f"Generated OPR CSV for {result['event_code']}",
                    "eventCode": result["event_code"],
                    "season": season,
                    "teamCount": result["team_count"],
                    "matchDetailsPath": match_details_path,
                    "outputPath": result["output_path"],
                    "matchDetailsGenerated": True,
                },
            )
        except json.JSONDecodeError:
            self._send_json(400, {"error": "Invalid JSON body."})
        except Exception as exc:  # noqa: BLE001
            self._send_json(500, {"error": f"Internal server error: {exc}"})

    def do_GET(self):
        if self.path == "/api/health":
            self._send_json(200, {"status": "ok"})
            return
        self._send_json(404, {"error": "Endpoint not found."})

    def _send_json(self, status_code, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Run the FTC Event Scout local server.")
    parser.add_argument("port", nargs="?", type=int, default=8000)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--data-dir", type=Path, default=Path.cwd())
    parser.add_argument("--resource-dir", type=Path, default=RESOURCE_ROOT)
    return parser.parse_args(argv[1:])


def prepare_data_directory(resource_dir, data_dir):
    """Stage seed CSVs in the app's disposable cache directory."""
    resource_dir = resource_dir.expanduser().resolve()
    data_dir = data_dir.expanduser().resolve()
    data_dir.mkdir(parents=True, exist_ok=True)

    for directory_name in ("event_results", "events_teams_opr"):
        source_dir = resource_dir / directory_name
        destination_dir = data_dir / directory_name
        destination_dir.mkdir(parents=True, exist_ok=True)
        if not source_dir.is_dir() or source_dir.resolve() == destination_dir.resolve():
            continue
        for source in source_dir.glob("*.csv"):
            destination = destination_dir / source.name
            if not destination.exists():
                shutil.copy2(source, destination)

    return data_dir


def first_available_port(start_port, max_tries=20):
    for offset in range(max_tries):
        candidate = start_port + offset
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if sock.connect_ex(("127.0.0.1", candidate)) != 0:
                return candidate
    return None


def main(argv=None):
    args = parse_args(argv or sys.argv)
    data_dir = prepare_data_directory(args.resource_dir, args.data_dir)
    os.chdir(data_dir)

    selected_port = first_available_port(args.port)
    if selected_port is None:
        print(f"Could not find an available port starting at {args.port}.", flush=True)
        return 1

    if selected_port != args.port:
        print(f"Port {args.port} is in use. Falling back to {selected_port}.", flush=True)

    server = ThreadingHTTPServer((args.host, selected_port), OPRAPIHandler)
    actual_port = server.server_address[1]
    url = f"http://{args.host}:{actual_port}"
    print(f"READY {url}", flush=True)
    print("API endpoint: POST /api/generate-opr", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
