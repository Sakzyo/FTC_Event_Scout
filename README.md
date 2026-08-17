# FTC Event Scout

FTC Event Scout is a native macOS SwiftUI application developed by Dylan from team #19600 Treeman for inspecting FIRST Tech Challenge events. It downloads match and score data from FIRST Events, calculates several Offensive Power Rating (OPR) estimates, and presents the results through native macOS tables, sidebars, toolbars, settings, and sheets.

The visible application is entirely SwiftUI. A bundled, loopback-only Python helper retrieves upstream data, writes disposable CSV files, and performs the OPR calculations. It does not serve HTML or any other user interface.

## What is OPR?

Offensive Power Rating estimates a team's average contribution to its alliance's score. Each alliance appearance becomes an equation in which the participating teams' estimated contributions add up to the alliance score; OPR is the least-squares solution across those equations.

OPR is an estimate rather than an official event ranking or a direct measurement of an individual robot. Partner schedules, defense, penalties, game design, and limited match data can all affect it. For a worked explanation, see [The Math Behind OPR — An Introduction](https://blog.thebluealliance.com/2017/10/05/the-math-behind-opr-an-introduction/).

This project calculates:

- Total OPR from final alliance scores
- Non-penalty OPR when penalty details are available
- Autonomous OPR
- Teleop-only OPR
- Endgame OPR

The calculator solves the normal equations with partial-pivot Gaussian elimination. If an event schedule produces a rank-deficient system, it applies a small deterministic ridge term before retrying.

## Current features

- Native `NavigationSplitView` navigation with Rankings and Highlights sections
- Sortable live-event rankings for event rank, team number, and every calculated OPR metric
- Pre-event FTCScout previews with team names, historical OPR, best season, recent seasons, and rookie year
- Highest final, non-penalty, autonomous, and teleop alliance-score highlights, including ties
- Per-team match-history sheets with results, partners, opponents, scores, and scouting tags
- Centered score-breakdown controls for every match; breakdowns start collapsed and can be opened with the mouse or keyboard
- Detailed red/blue score breakdowns for autonomous, driver-controlled, endgame, foul, and final-score fields supplied by FIRST
- Event/team-scoped scouting tags stored locally on the Mac
- Team numbers rendered as identifiers without thousands separators—for example, `10435`, not `10,435`
- Dedicated first-launch credential page, native Settings window, toolbar actions, and macOS menu commands

## Requirements

- macOS 14 or later
- A current Xcode installation for compiling the Swift package
- A discoverable Python 3 installation
- Internet access to FIRST Events and, for pre-event previews, FTCScout
- A FIRST Events API username and token

The Python helper uses only the Python standard library. There are no pip dependencies, virtual environments, or user-configurable interpreter paths. At runtime, the app searches common package-manager, framework, Conda, pyenv, asdf, mise, and `PATH` locations and selects the newest Python 3 version it finds. If no Python 3 interpreter is available, the app presents an installation page.

## Build and run

From the repository root:

```bash
./script/build_and_run.sh
```

This stops an existing FTC Event Scout process and helper, builds the debug configuration, assembles and ad-hoc signs `dist/FTC Event Scout.app`, and launches a fresh instance.

Additional modes:

```bash
./script/build_and_run.sh --verify     # launch and verify that the app remains running
./script/build_and_run.sh --debug      # start the packaged executable under LLDB
./script/build_and_run.sh --logs       # launch and stream process logs
./script/build_and_run.sh --telemetry  # launch and stream app-subsystem telemetry
```

Package without launching:

```bash
./script/package_app.sh debug
./script/package_app.sh release
```

The generated bundle is ad-hoc signed for local use; it is not Developer ID signed or notarized for distribution. Build output is written to `.build/swift-build.log`. The packager distinguishes source compilation failures from an incompatible selected Xcode toolchain and retries without SwiftPM's nested sandbox when running inside an already-sandboxed environment.

## First launch and normal use

If either FIRST Events credential is absent from the Keychain, the app opens a separate credential page before starting the local helper. Credentials can later be changed in **FTC Event Scout > Settings** (`⌘,`). A `401 Unauthorized` response means FIRST rejected the stored username/token pair.

After the helper is ready:

1. Enter a 2–24 character alphanumeric event code in the toolbar.
2. Press Return or select the Load button.
3. Select a team number in a live ranking to open its match history.
4. Select the centered **Score Breakdown** control within a match to reveal its red/blue details.

Available commands:

- **Scout > Load Event…** (`⌘L`) focuses the event-code field.
- **Scout > Refresh Event** (`⌘R`) regenerates the current event data.
- **Scout > Restart Data Service** (`⇧⌘R`) restarts the Python helper.

## Data flow

```text
Native SwiftUI toolbar and views
                |
                | POST /api/generate-opr
                v
Loopback Python service on 127.0.0.1
                |
       +--------+---------+
       |                  |
       v                  v
FIRST Events API     FTCScout GraphQL
       |                  |
       |                  +--> historical pre-event preview
       v
match/score data --> CSV generation --> OPR calculation
                                         |
                                         v
                         native rankings, highlights,
                         match history, and score details
```

For events with played matches, the helper requests both qualification and playoff match/score endpoints, writes match-detail and OPR CSV files, and returns their location to the Swift client. For a registered event with no matches, it requests the registered teams and historical quick statistics from FTCScout instead.

The active season is currently `2025` in `scrape.py` and `historical_opr.py`. `historical_opr.py` searches seasons 2019–2025 for each team's highest historical OPR, while the current preview table displays 2023–2025 explicitly. These constants and columns must be updated when the target FTC season changes.

## Local storage and security

- FIRST Events credentials: macOS login Keychain
- Team tags: `~/Library/Application Support/FTC Event Scout/team-tags.json`
- Last event and sort preferences: `UserDefaults`
- Regenerable match and OPR CSVs: `~/Library/Caches/FTC Event Scout/`

The helper receives credentials only through its process environment and binds only to `127.0.0.1`. It chooses an available local port at startup. Clearing the event cache in Settings removes regenerable CSV data without deleting Keychain credentials or team tags. Missing bundled seed CSV files are staged in the cache and can subsequently be refreshed from FIRST.

## Project structure

```text
Package.swift
Sources/FTCEventScout/
  App/                         SwiftUI app scenes and menu commands
  Models/                      Event records and observable application state
  Services/                    Backend process, API client, CSV, Keychain, tags, preferences
  Support/                     Shared display formatting
  Views/                       Rankings, highlights, match history, settings, and components
  Resources/                   Localization source and packaged strings
script/build_and_run.sh        Build, package, launch, debug, logs, and verification
script/package_app.sh          Debug/release .app assembly and ad-hoc signing
script/generate_app_icon.py    Standard-library app-icon generator
web_server.py                  Loopback JSON API; no web UI or root page
scrape.py                      FIRST Events API client and match-detail export
calculate_opr_from_csv.py      OPR metric preparation and CSV export
opr_calc.py                    Standard-library normal-equation solver
historical_opr.py              FTCScout pre-event preview client
event_results/                 Bundled seed match-detail CSVs
events_teams_opr/              Bundled seed OPR CSVs
```

## Local API development

The Python helper can be run directly from the repository root:

```bash
USERNAME=your_username TOKEN=your_token python3 web_server.py
```

It defaults to `127.0.0.1:8000` and prints the selected address. The app itself requests port `0`, allowing the operating system to select an available port.

Endpoints:

- `GET /api/health`
- `POST /api/generate-opr` with a JSON body such as `{"eventCode":"USIACMP"}`

All other routes, including `/`, return `404`. The API intentionally serves no static files.
