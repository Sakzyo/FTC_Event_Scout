# FTC Event Scout

FTC Event Scout is a native macOS SwiftUI app for reviewing FIRST Tech Challenge events. It refreshes event results from FIRST, calculates team Offensive Power Rating (OPR), and presents rankings, event highlights, team match histories, score breakdowns, historical pre-event previews, and Mac-local scouting tags with standard macOS controls.

SwiftUI owns all presentation, navigation, interaction, and persistence. A small loopback-only Python process performs upstream data retrieval and OPR calculation through a JSON API; it serves no user interface.

## Requirements

- macOS 14 or later
- A current Xcode installation for building the app
- The latest Python 3 installed on the Mac
- Internet access for FIRST Events and FTCScout
- FIRST Events API credentials

The Python helper uses only the standard library. There are no pip packages or Python interpreter settings to maintain. At startup, the app selects the newest Python 3 it can find and shows an installation page if none is available.

## Build and run

```bash
./script/build_and_run.sh
```

This builds, ad-hoc signs, packages, and launches `dist/FTC Event Scout.app`. Other useful modes are:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
```

Package without launching with `./script/package_app.sh debug` or `./script/package_app.sh release`.

The packager intentionally builds the single native implementation only. If the active Swift compiler and macOS SDK do not match, install a current Xcode release and select it with `xcode-select` before rebuilding.

## First launch and credentials

When either FIRST API credential is absent, the app opens a dedicated setup page. Credentials are stored in the macOS login Keychain. Update them later in **FTC Event Scout > Settings** (⌘,).

Enter an event code in the native toolbar and press Return. **Scout > Load Event…** (⌘L) focuses the field, **Refresh Event** (⌘R) refreshes the current event, and **Restart Data Service** (⇧⌘R) relaunches the local helper.

A FIRST `401 Unauthorized` response means the saved API username or token was rejected. Open Settings, verify both values, and save again.

## Native architecture

```text
SwiftUI toolbar and NavigationSplitView
                    |
                    v
        POST /api/generate-opr on loopback
                    |
       +------------+-------------+
       |                          |
       v                          v
FIRST Events API           FTCScout preview
       |
       v
match CSV -> OPR calculation -> native SwiftUI tables, sheets, and highlights
```

The app uses macOS storage conventions:

- Credentials: login Keychain
- Team tags: `~/Library/Application Support/FTC Event Scout/team-tags.json`
- UI preferences: `UserDefaults`
- Regenerable match and OPR CSV files: `~/Library/Caches/FTC Event Scout/`

Team tags are scoped to an event/team pair. Settings can clear cached event data without deleting tags or credentials.

## Project structure

```text
Package.swift
Sources/FTCEventScout/
  App/                         SwiftUI scenes and commands
  Models/                      Observable app state and event models
  Services/                    Keychain, preferences, tags, CSV, backend API
  Views/                       Native tables, split views, sheets, and settings
  Resources/Localizable.xcstrings
script/package_app.sh          Native app bundle packager
script/build_and_run.sh        Build, launch, debug, and verification entrypoint
web_server.py                  Loopback JSON API only; serves no user interface
scrape.py                      FIRST Events client using Python standard library
calculate_opr_from_csv.py      OPR data preparation and CSV export
opr_calc.py                    Standard-library least-squares solver
historical_opr.py              FTCScout pre-event preview
event_results/                 Bundled seed match data
events_teams_opr/              Bundled seed rankings
```

## Data behavior

For events with match data, the app displays total, non-penalty, auto, teleop-only, and endgame OPR. The native rankings table can be sorted using the controls above it. Selecting a live-event team opens a sheet containing every match, alliance result, partners, opponents, scores, tags, and a disclosure-based score breakdown.

Highlights show the top final, non-penalty, auto, and teleop alliance scores, including ties. If an event is registered but has no matches, the app displays an FTCScout historical preview with team name, highest OPR, best season, recent seasonal values, and rookie year.

The active season is currently `2025` in `scrape.py` and `historical_opr.py`; update those constants when the FTC season changes.

## Local API development

The helper can be run directly for backend development:

```bash
USERNAME=your_username TOKEN=your_token python3 web_server.py
```

It prints its loopback address. The available endpoints are:

- `GET /api/health`
- `POST /api/generate-opr` with `{"eventCode":"USIACMP"}`

There is deliberately no root page or static-file route.
