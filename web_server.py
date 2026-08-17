import json
import socket
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler

from calculate_opr_from_csv import generate_event_opr_csv
from historical_opr import fetch_event_preview
from scrape import generate_event_match_details_csv


def _looks_like_no_matches_error(exc):
    """Return True if the exception indicates the event simply has no matches yet."""
    msg = str(exc).lower()
    return "no matches found" in msg or "no matches for" in msg


class OPRWebHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        super().end_headers()

    def do_POST(self):
        if self.path != "/api/generate-opr":
            self.send_error(404, "Endpoint not found")
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(content_length).decode("utf-8")
            payload = json.loads(raw_body) if raw_body else {}
            event_code = str(payload.get("eventCode", "")).strip().upper()

            if not event_code:
                self._send_json(400, {"error": "eventCode is required."})
                return

            try:
                match_details_path = generate_event_match_details_csv(event_code)
            except Exception as exc:  # noqa: BLE001
                if _looks_like_no_matches_error(exc):
                    # Event has not started yet (no matches played). Fall back
                    # to ftcscout.org for a historical-OPR preview of the
                    # registered teams.
                    try:
                        preview = fetch_event_preview(event_code)
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
                                f"{event_code} has not started yet. Showing each "
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

            result = generate_event_opr_csv(event_code)
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

    def _send_json(self, status_code, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def parse_port(argv):
    if len(argv) < 2:
        return 8000

    try:
        return int(argv[1])
    except ValueError as exc:
        raise ValueError(f"Invalid port '{argv[1]}'. Use an integer like 8000.") from exc


def first_available_port(start_port, max_tries=20):
    for offset in range(max_tries):
        candidate = start_port + offset
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if sock.connect_ex(("127.0.0.1", candidate)) != 0:
                return candidate
    return None


if __name__ == "__main__":
    try:
        requested_port = parse_port(sys.argv)
    except ValueError as err:
        print(err)
        sys.exit(1)

    selected_port = first_available_port(requested_port)
    if selected_port is None:
        print(f"Could not find an available port starting at {requested_port}.")
        sys.exit(1)

    if selected_port != requested_port:
        print(f"Port {requested_port} is in use. Falling back to {selected_port}.")

    server = HTTPServer(("127.0.0.1", selected_port), OPRWebHandler)
    print(f"Serving on http://127.0.0.1:{selected_port}")
    print("API endpoint: POST /api/generate-opr")
    server.serve_forever()
