"""Normalize season-specific FTC score details for the native match UI."""


def first_value(source, *keys):
    for key in keys:
        value = source.get(key)
        if value is not None:
            return value
    return None


def _display(value):
    if value is None:
        return None
    if isinstance(value, bool):
        return "Yes" if value else "No"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, (list, tuple)):
        rendered = [_display(item) for item in value]
        return " / ".join(item for item in rendered if item is not None)
    return str(value).replace("_", " ").title()


def _pair(source, first_key, second_key):
    values = [source.get(first_key), source.get(second_key)]
    if all(value is None for value in values):
        return None
    return " · ".join(_display(value) if value is not None else "—" for value in values)


def _counts(source, *keys):
    values = [source.get(key) for key in keys]
    if all(value is None for value in values):
        return None
    return " / ".join(_display(value) if value is not None else "—" for value in values)


def _row(identifier, label, value, indent=0, emphasized=False):
    rendered = _display(value)
    if rendered is None:
        return None
    return {
        "id": identifier,
        "label": label,
        "value": rendered,
        "indent": indent,
        "emphasized": emphasized,
    }


def _rows(*rows):
    return [row for row in rows if row is not None]


def score_totals(
    season,
    score,
    match_auto=None,
    match_final=None,
    match_foul_awarded=None,
):
    """Return the cross-season totals used by OPR and event highlights."""
    season = int(season)
    if season == 2019:
        auto = first_value(score, "autonomousPoints", "autoPoints")
        driver_controlled = score.get("driverControlledPoints")
        endgame = first_value(score, "endGamePoints", "endgamePoints")
        teleop = _sum_available(driver_controlled, endgame)
        foul_committed = score.get("penaltyPoints")
        minor = score.get("minorPenalties")
        major = score.get("majorPenalties")
    elif season == 2020:
        auto = score.get("autoPoints")
        driver_controlled = score.get("dcPoints")
        endgame = score.get("endgamePoints")
        teleop = _sum_available(driver_controlled, endgame)
        foul_committed = score.get("penaltyPoints")
        minor = score.get("minorPenalties")
        major = score.get("majorPenalties")
    elif season == 2021:
        auto = score.get("autoPoints")
        driver_controlled = score.get("driverControlledPoints")
        endgame = score.get("endgamePoints")
        teleop = _sum_available(driver_controlled, endgame)
        foul_committed = score.get("penaltyPoints")
        minor = score.get("minorPenalties")
        major = score.get("majorPenalties")
    elif season in {2022, 2023}:
        auto = score.get("autoPoints")
        driver_controlled = score.get("dcPoints")
        endgame = score.get("endgamePoints")
        teleop = _sum_available(driver_controlled, endgame)
        foul_committed = score.get("penaltyPointsCommitted")
        minor = score.get("minorPenalties")
        major = score.get("majorPenalties")
    elif season == 2024:
        auto = score.get("autoPoints")
        teleop = score.get("teleopPoints")
        endgame = score.get("endGamePoints")
        foul_committed = score.get("foulPointsCommitted")
        minor = score.get("minorFouls")
        major = score.get("majorFouls")
    else:
        auto = first_value(score, "autoPoints", "autonomousPoints")
        teleop = first_value(
            score,
            "teleopPoints",
            "dcPoints",
            "driverControlledPoints",
        )
        endgame = first_value(
            score,
            "teleopBasePoints",
            "endGamePoints",
            "endgamePoints",
        )
        foul_committed = first_value(
            score,
            "foulPointsCommitted",
            "penaltyPointsCommitted",
            "penaltyPoints",
        )
        minor = first_value(score, "minorFouls", "minorPenalties")
        major = first_value(score, "majorFouls", "majorPenalties")

    return {
        "auto": auto if auto is not None else match_auto,
        "teleop": teleop,
        "endgame": endgame,
        "foul_awarded": match_foul_awarded,
        "foul_committed": foul_committed,
        "minor_fouls": minor,
        "major_fouls": major,
        "final": match_final,
    }


def _sum_available(*values):
    present = [value for value in values if value is not None]
    return sum(present) if present else None


def build_score_breakdown_rows(
    season,
    score,
    opponent_score,
    match_auto=None,
    match_final=None,
    match_foul_awarded=None,
):
    """Create ordered display rows matching the official season breakdown."""
    season = int(season)
    builders = {
        2019: _skystone_rows,
        2020: _ultimate_goal_rows,
        2021: _freight_frenzy_rows,
        2022: _powerplay_rows,
        2023: _centerstage_rows,
        2024: _into_the_deep_rows,
        2025: _decode_rows,
    }
    totals = score_totals(
        season,
        score,
        match_auto=match_auto,
        match_final=match_final,
        match_foul_awarded=match_foul_awarded,
    )
    builder = builders.get(season)
    rows = builder(score, totals) if builder else _generic_rows(totals)
    rows.extend(_penalty_and_final_rows(opponent_score, totals))
    return rows


def _skystone_rows(score, totals):
    foundation_points = None
    if score.get("foundationMoved") is not None:
        foundation_points = 15 if score["foundationMoved"] else 0
    return _rows(
        _row("auto", "Autonomous", totals["auto"], emphasized=True),
        _row("auto-navigation-status", "Navigated (Robot 1 / 2)", _pair(score, "robot1Navigated", "robot2Navigated"), 1),
        _row("auto-stones", "Auto Stones", score.get("autoStones"), 1),
        _row("auto-delivered", "Auto Delivered", score.get("autoDelivered"), 1),
        _row("auto-placed", "Auto Placed", score.get("autoPlaced"), 1),
        _row("auto-returned", "Auto Returned", score.get("autoReturned"), 1),
        _row("auto-first-skystone", "First Returned Is Skystone", score.get("firstReturnedIsSkystone"), 1),
        _row("auto-delivery-points", "Stone Delivery", score.get("autoDeliveryPoints"), 1),
        _row("auto-placed-points", "Placing", score.get("autoPlacedPoints"), 1),
        _row("auto-repositioned-points", "Repositioning", score.get("repositionedPoints"), 1),
        _row("auto-navigation-points", "Navigating", score.get("navigationPoints"), 1),
        _row("driver", "Driver Controlled", score.get("driverControlledPoints"), emphasized=True),
        _row("driver-delivered", "Delivered", score.get("driverControlledDelivered"), 1),
        _row("driver-placed", "Placed", score.get("driverControlledPlaced"), 1),
        _row("driver-returned", "Returned", score.get("driverControlledReturned"), 1),
        _row("driver-skyscraper", "Tallest Skyscraper", score.get("tallestSkyscraper"), 1),
        _row("driver-delivery-points", "Stone Delivery", score.get("driverControlledDeliveryPoints"), 1),
        _row("driver-placed-points", "Placing", score.get("driverControlledPlacedPoints"), 1),
        _row("driver-skyscraper-points", "Skyscraper Bonus", score.get("skyscraperBonusPoints"), 1),
        _row("endgame", "End Game", totals["endgame"], emphasized=True),
        _row("endgame-capstone-level", "Capstone Level (Robot 1 / 2)", _pair(score, "robot1CapstoneLevel", "robot2CapstoneLevel"), 1),
        _row("endgame-parked", "Parked (Robot 1 / 2)", _pair(score, "robot1Parked", "robot2Parked"), 1),
        _row("endgame-capping", "Capping", score.get("capstonePoints"), 1),
        _row("endgame-foundation", "Foundation Moved", foundation_points, 1),
        _row("endgame-parking", "Parking", score.get("parkingPoints"), 1),
    )


def _ultimate_goal_rows(score, totals):
    return _rows(
        _row("auto", "Autonomous", totals["auto"], emphasized=True),
        _row("auto-navigated", "Navigated (Robot 1 / 2)", _pair(score, "navigated1", "navigated2"), 1),
        _row("auto-wobble-delivered", "Wobble Delivered (Robot 1 / 2)", _pair(score, "wobbleDelivered1", "wobbleDelivered2"), 1),
        _row("auto-tower-counts", "Tower (Low / Middle / High)", _counts(score, "autoTowerLow", "autoTowerMid", "autoTowerHigh"), 1),
        _row("auto-tower-points", "Tower Points", score.get("autoTowerPoints"), 1),
        _row("auto-power-shots", "Power Shot (Left / Center / Right)", _counts(score, "autoPowerShotLeft", "autoPowerShotCenter", "autoPowerShotRight"), 1),
        _row("auto-power-shot-points", "Power Shot Points", score.get("autoPowerShotPoints"), 1),
        _row("auto-wobble-points", "Wobble Points", score.get("autoWobblePoints"), 1),
        _row("driver", "Driver Controlled", score.get("dcPoints"), emphasized=True),
        _row("driver-tower-counts", "Tower (Low / Middle / High)", _counts(score, "dcTowerLow", "dcTowerMid", "dcTowerHigh"), 1),
        _row("endgame", "End Game", totals["endgame"], emphasized=True),
        _row("endgame-power-shots", "Power Shot (Left / Center / Right)", _counts(score, "endPowerShotLeft", "endPowerShotCenter", "endPowerShotRight"), 1),
        _row("endgame-power-shot-points", "Power Shot Points", score.get("endPowerShotPoints"), 1),
        _row("endgame-rings", "Rings (Robot 1 / 2)", _pair(score, "wobbleRings1", "wobbleRings2"), 1),
        _row("endgame-wobble", "Wobble Goal (Robot 1 / 2)", _pair(score, "wobbleEnd1", "wobbleEnd2"), 1),
        _row("endgame-ring-points", "Ring Points", score.get("wobbleRingPoints"), 1),
        _row("endgame-wobble-points", "Wobble Goal Points", score.get("wobbleEndPoints"), 1),
    )


def _freight_frenzy_rows(score, totals):
    return _rows(
        _row("auto", "Autonomous", totals["auto"], emphasized=True),
        _row("auto-barcode", "Barcode Element (Robot 1 / 2)", _pair(score, "barcodeElement1", "barcodeElement2"), 1),
        _row("auto-carousel", "Delivered Duck", score.get("carousel"), 1),
        _row("auto-navigation", "Navigated (Robot 1 / 2)", _pair(score, "autoNavigated1", "autoNavigated2"), 1),
        _row("auto-freight-counts", "Freight (Storage / L1 / L2 / L3)", _counts(score, "autoStorageFreight", "autoFreight1", "autoFreight2", "autoFreight3"), 1),
        _row("auto-bonus", "Bonus (Robot 1 / 2)", _pair(score, "autoBonus1", "autoBonus2"), 1),
        _row("auto-carousel-points", "Carousel Points", score.get("carouselPoints"), 1),
        _row("auto-navigation-points", "Navigation Points", score.get("autoNavigationPoints"), 1),
        _row("auto-freight-points", "Freight Points", score.get("autoFreightPoints"), 1),
        _row("auto-bonus-points", "Bonus Points", score.get("autoBonusPoints"), 1),
        _row("driver", "Driver Controlled", score.get("driverControlledPoints"), emphasized=True),
        _row("driver-freight-counts", "Freight (Storage / L1 / L2 / L3)", _counts(score, "driverControlledStorageFreight", "driverControlledFreight1", "driverControlledFreight2", "driverControlledFreight3"), 1),
        _row("driver-shared-freight", "Shared Hub Freight", score.get("sharedFreight"), 1),
        _row("driver-alliance-points", "Alliance Hub Freight", score.get("driverControlledAllianceHubPoints"), 1),
        _row("driver-shared-points", "Shared Hub Freight Points", score.get("driverControlledSharedHubPoints"), 1),
        _row("driver-storage-points", "Storage Freight Points", score.get("driverControlledStoragePoints"), 1),
        _row("endgame", "End Game", totals["endgame"], emphasized=True),
        _row("endgame-delivered", "Duck / Team Element Delivered", score.get("endgameDelivered"), 1),
        _row("endgame-balanced", "Alliance Hub Balanced", score.get("allianceBalanced"), 1),
        _row("endgame-unbalanced", "Shared Hub Unbalanced", score.get("sharedUnbalanced"), 1),
        _row("endgame-parked", "Parked (Robot 1 / 2)", _pair(score, "endgameParked1", "endgameParked2"), 1),
        _row("endgame-capped", "Shipping Hub Capped", score.get("capped"), 1),
        _row("endgame-delivery-points", "Delivery Points", score.get("endgameDeliveryPoints"), 1),
        _row("endgame-balanced-points", "Alliance Hub Balanced Points", score.get("allianceBalancedPoints"), 1),
        _row("endgame-unbalanced-points", "Shared Hub Status Points", score.get("sharedUnbalancedPoints"), 1),
        _row("endgame-parking-points", "Parking Points", score.get("endgameParkingPoints"), 1),
        _row("endgame-capping-points", "Capping Points", score.get("cappingPoints"), 1),
    )


def _powerplay_rows(score, totals):
    return _rows(
        _row("auto", "Auto", totals["auto"], emphasized=True),
        _row("auto-signal", "Signal Sleeve (Robot 1 / 2)", _pair(score, "initSignalSleeve1", "initSignalSleeve2"), 1),
        _row("auto-navigation", "Navigation (Robot 1 / 2)", _pair(score, "robot1Auto", "robot2Auto"), 1),
        _row("auto-junction-counts", "Junction Cones (Ground / Low / Medium / High)", score.get("autoJunctionCones"), 1),
        _row("auto-terminal", "Terminal Cones", score.get("autoTerminal"), 1),
        _row("auto-navigation-points", "Navigation Points", score.get("autoNavigationPoints"), 1),
        _row("auto-bonus-points", "Bonus Points", score.get("signalBonusPoints"), 1),
        _row("auto-junction-points", "Junction Cone Points", score.get("autoJunctionConePoints"), 1),
        _row("auto-terminal-points", "Terminal Points", score.get("autoTerminalConePoints"), 1),
        _row("driver", "Driver Controlled", score.get("dcPoints"), emphasized=True),
        _row("driver-junction-counts", "Junction Cones (Ground / Low / Medium / High)", score.get("dcJunctionCones"), 1),
        _row("driver-terminal", "Terminal Cones (Near / Far)", _counts(score, "dcTerminalNear", "dcTerminalFar"), 1),
        _row("driver-junction-points", "Junction Cone Points", score.get("dcJunctionConePoints"), 1),
        _row("driver-terminal-points", "Terminal Points", score.get("dcTerminalConePoints"), 1),
        _row("endgame", "End Game", totals["endgame"], emphasized=True),
        _row("endgame-navigation", "Navigated (Robot 1 / 2)", _pair(score, "egNavigated1", "egNavigated2"), 1),
        _row("endgame-beacons", "Beacons", score.get("beacons"), 1),
        _row("endgame-owned-junctions", "Owned Junctions", score.get("ownedJunctions"), 1),
        _row("endgame-circuit", "Circuit", score.get("circuit"), 1),
        _row("endgame-navigation-points", "Navigation Points", score.get("egNavigationPoints"), 1),
        _row("endgame-ownership-points", "Ownership Points", score.get("ownershipPoints"), 1),
        _row("endgame-circuit-points", "Circuit Points", score.get("circuitPoints"), 1),
    )


def _centerstage_rows(score, totals):
    return _rows(
        _row("auto", "Auto", totals["auto"], emphasized=True),
        _row("auto-team-prop", "Team Prop (Robot 1 / 2)", _pair(score, "initTeamProp1", "initTeamProp2"), 1),
        _row("auto-navigation", "Navigated (Robot 1 / 2)", _pair(score, "robot1Auto", "robot2Auto"), 1),
        _row("auto-spike-mark", "Spike Mark Pixel (Robot 1 / 2)", _pair(score, "spikeMarkPixel1", "spikeMarkPixel2"), 1),
        _row("auto-target-backdrop", "Target Backdrop Pixel (Robot 1 / 2)", _pair(score, "targetBackdropPixel1", "targetBackdropPixel2"), 1),
        _row("auto-backdrop-count", "Backdrop Pixels", score.get("autoBackdrop"), 1),
        _row("auto-backstage-count", "Backstage Pixels", score.get("autoBackstage"), 1),
        _row("auto-backdrop-points", "Backdrop Points", score.get("autoBackdropPoints"), 1),
        _row("auto-backstage-points", "Backstage Points", score.get("autoBackstagePoints"), 1),
        _row("auto-navigation-points", "Navigation Points", score.get("autoNavigatingPoints"), 1),
        _row("auto-randomization-points", "Randomization", score.get("autoRandomizationPoints"), 1),
        _row("driver", "Driver Controlled", score.get("dcPoints"), emphasized=True),
        _row("driver-backdrop-count", "Backdrop Pixels", score.get("dcBackdrop"), 1),
        _row("driver-backstage-count", "Backstage Pixels", score.get("dcBackstage"), 1),
        _row("driver-mosaics", "Mosaics", score.get("mosaics"), 1),
        _row("driver-set-line", "Maximum Set Line", score.get("maxSetLine"), 1),
        _row("driver-backdrop-points", "Backdrop Points", score.get("dcBackdropPoints"), 1),
        _row("driver-backstage-points", "Backstage Points", score.get("dcBackstagePoints"), 1),
        _row("driver-mosaic-points", "Mosaic Points", score.get("mosaicPoints"), 1),
        _row("driver-set-points", "Set Bonus Points", score.get("setBonusPoints"), 1),
        _row("endgame", "End Game", totals["endgame"], emphasized=True),
        _row("endgame-location", "Location (Robot 1 / 2)", _pair(score, "egRobot1", "egRobot2"), 1),
        _row("endgame-drones", "Drone Zone (Robot 1 / 2)", _pair(score, "drone1", "drone2"), 1),
        _row("endgame-location-points", "Location Points", score.get("egLocationPoints"), 1),
        _row("endgame-drone-points", "Drone Points", score.get("egDronePoints"), 1),
    )


def _into_the_deep_rows(score, totals):
    return _rows(
        _row("auto", "Total Auto", totals["auto"], emphasized=True),
        _row("auto-samples", "Samples (Net / Low / High)", _counts(score, "autoSampleNet", "autoSampleLow", "autoSampleHigh"), 1),
        _row("auto-sample-points", "Sample Points", score.get("autoSamplePoints"), 1),
        _row("auto-specimens", "Specimens (Low / High)", _counts(score, "autoSpecimenLow", "autoSpecimenHigh"), 1),
        _row("auto-specimen-points", "Specimen Points", score.get("autoSpecimenPoints"), 1),
        _row("auto-location", "Robot Location (Robot 1 / 2)", _pair(score, "robot1Auto", "robot2Auto"), 1),
        _row("teleop", "Total Teleop", totals["teleop"], emphasized=True),
        _row("teleop-samples", "Samples (Net / Low / High)", _counts(score, "teleopSampleNet", "teleopSampleLow", "teleopSampleHigh"), 1),
        _row("teleop-sample-points", "Sample Points", score.get("teleopSamplePoints"), 1),
        _row("teleop-specimens", "Specimens (Low / High)", _counts(score, "teleopSpecimenLow", "teleopSpecimenHigh"), 1),
        _row("teleop-specimen-points", "Specimen Points", score.get("teleopSpecimenPoints"), 1),
        _row("teleop-location", "Robot Location (Robot 1 / 2)", _pair(score, "robot1Teleop", "robot2Teleop"), 1),
        _row("teleop-park-points", "Parking Points", score.get("teleopParkPoints"), 1),
        _row("teleop-ascent-points", "Ascent Points", score.get("teleopAscentPoints"), 1),
    )


def _decode_rows(score, totals):
    return _rows(
        _row("auto", "Auto", totals["auto"], emphasized=True),
        _row("auto-classified", "Classified Artifacts", score.get("autoClassifiedArtifacts"), 1),
        _row("auto-overflow", "Overflow Artifacts", score.get("autoOverflowArtifacts"), 1),
        _row("auto-leave", "Location (Robot 1 / 2)", _pair(score, "robot1Auto", "robot2Auto"), 1),
        _row("auto-classifier", "Classifier State", _decode_classifier(score.get("autoClassifierState")), 1),
        _row("auto-leave-points", "Leave Points", score.get("autoLeavePoints"), 1),
        _row("auto-artifact-points", "Artifact Points", score.get("autoArtifactPoints"), 1),
        _row("auto-pattern-points", "Pattern Points", score.get("autoPatternPoints"), 1),
        _row("teleop", "Teleop", totals["teleop"], emphasized=True),
        _row("teleop-classified", "Classified Artifacts", score.get("teleopClassifiedArtifacts"), 1),
        _row("teleop-overflow", "Overflow Artifacts", score.get("teleopOverflowArtifacts"), 1),
        _row("teleop-depot", "Depot Artifacts", score.get("teleopDepotArtifacts"), 1),
        _row("teleop-base", "Base (Robot 1 / 2)", _pair(score, "robot1Teleop", "robot2Teleop"), 1),
        _row("teleop-classifier", "Classifier State", _decode_classifier(score.get("teleopClassifierState")), 1),
        _row("teleop-artifact-points", "Artifact Points", score.get("teleopArtifactPoints"), 1),
        _row("teleop-depot-points", "Depot Points", score.get("teleopDepotPoints"), 1),
        _row("teleop-pattern-points", "Pattern Points", score.get("teleopPatternPoints"), 1),
        _row("teleop-base-points", "Base Points", score.get("teleopBasePoints"), 1),
    )


def _decode_classifier(value):
    if value is None:
        return None
    if isinstance(value, (list, tuple)):
        return [_decode_classifier(item) for item in value]
    abbreviations = {
        "GREEN": "G",
        "PURPLE": "P",
        "NONE": "N",
    }
    return abbreviations.get(str(value).strip().upper(), value)


def _generic_rows(totals):
    return _rows(
        _row("auto", "Autonomous", totals["auto"], emphasized=True),
        _row("teleop", "Teleop", totals["teleop"], emphasized=True),
        _row("endgame", "End Game", totals["endgame"], emphasized=True),
    )


def _penalty_and_final_rows(opponent_score, totals):
    opponent_minor = first_value(opponent_score, "minorFouls", "minorPenalties")
    opponent_major = first_value(opponent_score, "majorFouls", "majorPenalties")
    return _rows(
        _row("penalty", "Penalty Points Awarded", totals["foul_awarded"], emphasized=True),
        _row("penalty-minor", "Opponent Minor Fouls", opponent_minor, 1),
        _row("penalty-major", "Opponent Major Fouls", opponent_major, 1),
        _row("final", "Final Score", totals["final"], emphasized=True),
    )
