# FTC Event OPR Scout

FTC Event OPR Scout is a native macOS app with an embedded local dashboard for inspecting FIRST Tech Challenge event results and estimating each team's scoring contribution with Offensive Power Rating (OPR). Enter an FTC event code to refresh its match data from the official FIRST API, calculate several OPR variants, and explore sortable rankings, event highlights, team match histories, score breakdowns, and Mac-local scouting tags.

New to OPR? The Blue Alliance's [The Math Behind OPR — An Introduction](https://blog.thebluealliance.com/2017/10/05/the-math-behind-opr-an-introduction/) explains the core idea, assumptions, and least-squares math behind the metric.

If an event has registered teams but no matches yet, the dashboard falls back to FTCScout and shows each team's highest historical OPR instead.

## What it does

- Downloads qualification and playoff matches from the FIRST Events API.
- Combines match metadata with detailed alliance score breakdowns.
- Calculates total, non-penalty, autonomous, teleop-only, and endgame OPR.
- Saves both raw match details and derived team rankings as CSV files.
- Shows event high scores, match histories, alliance score breakdowns, and sortable rankings.
- Stores custom team tags and colors in the embedded WebKit view's local storage.
- Shows a historical FTCScout preview when an event has not started.

## Project structure

```text
FTC_Event_Scout/
├── Package.swift                 # SwiftPM macOS executable
├── Sources/FTCEventScout/        # SwiftUI app, WebKit bridge, settings, services
├── Sources/AppKitFallback/       # Equivalent shell for mismatched Swift toolchains
├── script/build_and_run.sh       # Build, package, launch, and verify entrypoint
├── script/package_app.sh         # Creates dist/FTC Event Scout.app
├── script/generate_app_icon.py   # Generates the macOS app icon
├── index.html                    # Dashboard markup and client-side behavior
├── styles.css                   # Apple-style adaptive dashboard and modal styling
├── web_server.py                # Static server and POST /api/generate-opr
├── scrape.py                    # FIRST API client and match CSV generation
├── calculate_opr_from_csv.py    # CSV parsing, metric calculation, and exports
├── opr_calc.py                  # NumPy least-squares OPR solver
├── historical_opr.py            # FTCScout GraphQL pre-event fallback
├── event.py                     # Legacy Event container; currently unused
├── credentials.env              # Local FIRST API credentials (sensitive)
├── event_results/               # Per-event match-detail CSV files
├── events_teams_opr/            # Per-event team OPR ranking CSV files
├── .vscode/settings.json        # Workspace Python environment preference
└── __pycache__/                 # Generated Python bytecode; not source
```

The repository currently includes paired match-detail and OPR exports for 29 events. The match files contain 1,888 match rows, and the ranking files contain 933 event/team rows.

## Requirements

- Python 3.9 or newer (the project has been verified with Python 3.13)
- Internet access for FIRST and FTCScout requests
- FIRST Events API credentials
- Python packages:
  - `numpy`
  - `requests`

Install the backend packages into the Python runtime the app will use:

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
```

## Configuration

On first launch, the macOS app shows a dedicated credential page when either the FIRST API username or token is missing. Enter both values and select **Save and Continue**. The app stores them in the macOS login Keychain and passes them only to its local server process. You can update them later from **FTC Event Scout > Settings** (⌘,).

In the app, enter event codes from the native toolbar field and press Return. **Scout > Load Event…** (⌘L) focuses that field, **Reload Dashboard** (⌘R) reloads the current view, and **Restart Local Server** (⇧⌘R) cleanly relaunches the bundled backend. Settings opens in its own macOS window rather than interrupting the dashboard with a modal alert.

The app automatically finds the newest installed Python 3 interpreter each time it starts. When the same Python version is installed in more than one location, it prefers the copy that can import the required `numpy` and `requests` packages. There is no Python preference to maintain. If Python or its required packages are unavailable, the app shows a dedicated recovery page before launching the server.

For the command-line web server, create or update `credentials.env` in the project root:

```dotenv
USERNAME=your_first_api_username
TOKEN=your_first_api_token
```

The standalone server reads credentials when an event refresh is requested. `credentials.env` is ignored by Git and should never be published or copied into the app bundle.

The active FTC season is currently hard-coded as `2025` in `scrape.py`. The FTCScout event lookup also defaults to 2025 in `historical_opr.py`. Update both constants when moving the application to another season; also review `HISTORICAL_SEASONS` in `historical_opr.py`.

## Build and run the macOS app

Use the project entrypoint (also exposed as the Codex **Run** action):

```bash
./script/build_and_run.sh
```

This creates and launches `dist/FTC Event Scout.app`. Optional modes are:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

To package without launching, run `./script/package_app.sh debug` or `./script/package_app.sh release`. The bundle is ad-hoc signed for local use. Distribution through Gatekeeper or the Mac App Store still requires an Apple Developer identity, hardened-runtime signing, and notarization.

The packager prefers the SwiftUI executable. If the installed Command Line Tools contain an incompatible Swift compiler/SDK/SwiftPM combination, it automatically builds the equivalent AppKit shell so a usable app is still produced; details are written to `.build/swift-build.log`.

Generated CSV files are stored in `~/Library/Application Support/FTC Event Scout/`. Seed CSVs are copied there on first launch, while the source copies remain unchanged.

## Run the standalone dashboard

Start the server from the project root so its relative data paths resolve correctly:

```bash
python3 web_server.py
```

The default address is <http://127.0.0.1:8000>. A different starting port can be supplied:

```bash
python3 web_server.py 8080
```

If that port is occupied, the server checks the next 19 ports and prints the address it selected. Open the printed URL, enter an event code such as `USIACMP`, and select **Load Event**.

Do not open `index.html` directly from the filesystem. The page depends on the local POST endpoint and on CSV files served over HTTP.

## Data flow

```text
Event code entered in browser
          |
          v
POST /api/generate-opr
          |
          v
FIRST Events API -----> event_results/<EVENT> Match Details.csv
                                  |
                                  v
                       OPR least-squares calculation
                                  |
                                  v
                       events_teams_opr/<EVENT> OPR.csv
                                  |
                                  v
                         Browser table and summaries

If FIRST returns no matches:
FTCScout GraphQL API --> registered teams + highest historical OPR preview
```

For a normal event load, `web_server.py` performs these steps:

1. Validate and uppercase the event code.
2. Request qualification and playoff match lists and score details from FIRST.
3. Flatten the alliance teams and score components into a match-detail CSV.
4. Build alliance participation equations for every available OPR metric.
5. Calculate and export the team's OPR values.
6. Return the generated paths to the browser, which then loads both CSV files.

If FIRST reports no matches, the server queries FTCScout for registered teams and their 2019-2025 quick-stat history. That preview is returned as JSON and is not written to the two CSV directories.

## How OPR is calculated

For each alliance appearance, the application assumes:

```text
team 1 contribution + team 2 contribution = alliance score
```

Across an event this becomes the least-squares system `Mx = s`, where:

- `M` is a binary matrix marking which teams appeared in each alliance.
- `s` is the alliance score vector for one metric.
- `x` is the estimated per-team contribution vector.

The solver uses the normal equation `(M^T M)x = M^T s`. If the matrix is singular, `opr_calc.py` falls back to a NumPy pseudoinverse.

The exported metrics are:

| Column | Meaning |
| --- | --- |
| `OPR` | Contribution to the final alliance score, including awarded penalty points. |
| `npOPR` / `OPR No Penalty Scored` | Contribution to final score after removing penalty points awarded by the opponent. |
| `Auto OPR` / `OPR Auto` | Contribution to autonomous-period points. |
| `Teleop OPR` / `OPR Teleop Only` | Contribution to teleop points excluding endgame/base points. |
| `Endgame OPR` / `OPR Endgame` | Contribution to endgame/base points. |

Stored rankings are ordered by non-penalty OPR. OPR is an estimate based on alliance results, not a direct measurement of an individual robot, and is less stable when an event has few matches or a poorly conditioned participation matrix.

## CSV files

### Match details

`event_results/<EVENT_CODE> Match Details.csv` contains one row per match, with:

- series and match number;
- two on-field teams for each alliance;
- autonomous, teleop, endgame/base, foul, and final scores;
- detailed artifact, pattern, depot, leave, and foul fields when supplied by FIRST.

The checked-in snapshot contains two compatible schemas. Older files have 32 columns; newer files have 40 and add classified/overflow artifact counts for both alliances. Missing team slots may occur in the source data and are ignored when equations are built.

### OPR rankings

`events_teams_opr/<EVENT_CODE> OPR.csv` contains one row per team and seven columns: rank, team number, and the five OPR metrics.

Two header naming styles are present because the batch exporter and single-event web exporter use different labels. The values have the same meanings, and the dashboard supports either form.

## Command-line workflows

Fetch one event's match data interactively:

```bash
python3 scrape.py
```

Recalculate every CSV already present in `event_results/`, rewrite the corresponding OPR exports, and print each event's top ten non-penalty OPR values:

```bash
python3 calculate_opr_from_csv.py
```

Query the FTCScout historical preview directly (the default code is `AEDUS` if omitted):

```bash
python3 historical_opr.py AEDUS
```

Call the local API without the browser:

```bash
curl -X POST http://127.0.0.1:8000/api/generate-opr \
  -H 'Content-Type: application/json' \
  -d '{"eventCode":"USIACMP"}'
```

The POST request refreshes and overwrites that event's generated CSV files. A successful response is either a normal generation result with file paths and team count, or a `mode: "preview"` result containing registered teams and historical OPR data.

## Frontend behavior

- Selecting column headers sorts the table; when sorting away from the stored rank, the UI inserts a dynamic ranking column.
- Selecting a team number opens all of that team's matches with alliance, opponent, result, and expandable score details.
- Event highlight cards show the highest final, non-penalty, auto, and teleop alliance scores, including ties.
- Tags are scoped to an event/team pair and remain in the app's local WebKit storage; they are not written to CSV or shared between users.
- The local server sends no-cache headers so regenerated CSVs appear immediately.

## Development notes and limitations

- There is no automated test suite or dependency lock file yet.
- The HTTP server is single-process and intended for trusted local use, not public deployment.
- Upstream requests happen synchronously during a POST and can take several seconds.
- The browser CSV parser is intentionally simple and splits on commas; the generated files currently contain numeric fields without quoted commas.
- `event.py` is not imported by the active pipeline.
- `index.html` contains unused client-side OPR/export helpers; the active path uses the Python calculation and generated server-side CSV.
- Existing CSVs can be recalculated offline. The standalone server can start without FIRST credentials, while the macOS app requires credentials before it starts its embedded server.

## Troubleshooting

**FIRST API credentials are missing.**

In the macOS app, enter both values on the startup credential page, or update them later in Settings (⌘,). For the standalone server, confirm that `credentials.env` is in the project root and contains both variable names.

**The local server cannot start.**

Install Python 3 from the official Python for macOS download page if the app shows **Python 3 Required**. The app selects the newest Python 3 it finds automatically and preflights `numpy` and `requests`. If all copies of that version are missing a package, the app shows the exact interpreter-specific installation command before launching the server.

**The page loads, but event generation fails.**  
Check the event code, the configured season, your FIRST API credentials, and network access. The error returned by the upstream API is displayed in the dashboard status area.

**The expected port is different.**  
The requested port was already occupied. Use the fallback URL printed by `web_server.py`.

**The browser shows stale or missing CSV data.**  
Run the server from the project root and access the page through its `http://127.0.0.1:<port>` URL rather than opening the HTML file directly.
