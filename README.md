<p align="center">
  <img src="docs/assets/app-icon.svg" width="112" alt="FTC Event Scout application icon">
</p>

<h1 align="center">FTC Event Scout</h1>

<p align="center">
  A native macOS app that turns FIRST Tech Challenge event data into sortable OPR rankings, score highlights, and match-level scouting views.
</p>

<p align="center">
  <a href="#installation"><img src="https://img.shields.io/badge/Build_for_macOS-14%2B-0A84FF?style=for-the-badge&logo=apple&logoColor=white" alt="Build FTC Event Scout for macOS 14 or later"></a>
</p>

<p align="center">
  <img src="docs/assets/app-demo.png" width="1100" alt="FTC Event Scout displaying sortable OPR rankings for a loaded event">
</p>

**FTC Event Scout** is a native **macOS scouting app** for exploring FIRST Tech Challenge events. It combines live rankings, score highlights, team match history, detailed score breakdowns, and locally stored scouting tags in a SwiftUI interface.

Choose a season and enter an event code; a loopback-only Python helper fetches FIRST Events data, generates CSVs, and calculates least-squares OPR estimates for total, non-penalty, autonomous, teleop, and endgame performance. The app turns those results into sortable tables so scouts can compare teams and inspect individual matches.

The visible application is entirely native SwiftUI, while the Python helper uses only the standard library and listens on `127.0.0.1`. FIRST Events credentials are stored in private app data on the Mac; the unencrypted token file is restricted to the current user. When an event has not started, FTCScout data provides a historical preview of its registered teams.


## Getting started

### Installation

A prebuilt release is not currently published, so installation is from source.

1. Use macOS 14 or later and install Xcode 15.3 or later plus Python 3.
2. Clone the repository using the commands in [Development](#development).
3. Run `./script/package_app.sh release` to create `dist/FTC Event Scout.app`.
4. Move the app to `Applications`, launch it, and enter your FIRST Events API username and token.

By default, the locally built app is ad-hoc signed; it is not Developer ID signed or notarized.

### Development

Development requires macOS 14+, Xcode with Swift 5.10+ support, and Python 3; loading live data also requires FIRST Events API credentials.

```sh
git clone https://github.com/Sakzyo/FTC_Event_Scout.git
cd FTC_Event_Scout
./script/build_and_run.sh
```

The script builds the `FTCEventScout` executable target, assembles `dist/FTC Event Scout.app`, ad-hoc signs it, and launches it.

For build-only workflows:

```sh
./script/package_app.sh debug
./script/package_app.sh release
```

To create the release app, compressed GitHub release DMG, and SHA-256 checksum:

```sh
./script/package_dmg.sh
```


## Repo layout

```text
FTC_Event_Scout/
├── Package.swift                    ← SwiftPM manifest and FTCEventScout target
├── Sources/FTCEventScout/           ← native macOS application
│   ├── App/                         app entry point, scenes, and commands
│   ├── Models/                      event records and observable app state
│   ├── Services/                    backend, API, CSV, credentials, tags, preferences
│   ├── Support/                     shared formatting helpers
│   ├── Views/                       rankings, highlights, match history, settings
│   │   └── Components/              reusable SwiftUI components
│   └── Resources/                   localized strings
├── script/                          ← build, package, launch, and icon tooling
├── web_server.py                    loopback JSON service used by the app
├── scrape.py                        FIRST Events client and match CSV export
├── score_breakdown.py               season-specific score detail normalization
├── historical_opr.py                FTCScout pre-event history client
├── calculate_opr_from_csv.py        OPR metric preparation and CSV export
├── opr_calc.py                      standard-library least-squares solver
├── event_results/                   bundled seed match-detail CSVs
├── events_teams_opr/                bundled seed OPR CSVs
├── tests/                            season-specific score breakdown tests
└── docs/assets/                     README icon and application capture
```
