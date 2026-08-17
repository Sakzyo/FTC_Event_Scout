import csv
import glob
import math
import os

from opr_calc import opr_calc

RESULTS_DIR = "event_results"
OPR_EXPORT_DIR = "events_teams_opr"
METRIC_ORDER = [
    "opr_total",
    "opr_no_penalty",
    "opr_auto",
    "opr_teleop",
    "opr_endgame",
]


def parse_float(value):
    text = (value or "").strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def first_number(row, keys):
    for key in keys:
        value = parse_float(row.get(key))
        if value is not None:
            return value
    return None


def parse_match_rows(csv_path):
    """Return alliance equations with all score components needed for OPR metrics."""
    equations = []

    def parse_alliance_teams(row, alliance_prefix):
        teams = []
        for slot in ("1", "2"):
            value = (row.get(f"{alliance_prefix}{slot} Team Number") or "").strip()
            if value:
                teams.append(int(value))
        return teams

    with open(csv_path, mode="r", encoding="utf-8-sig", newline="") as csv_file:
        reader = csv.DictReader(csv_file)
        for row in reader:
            red_teams = parse_alliance_teams(row, "Red")
            blue_teams = parse_alliance_teams(row, "Blue")

            red_final = first_number(row, ["Red Final Score"])
            blue_final = first_number(row, ["Blue Final Score"])

            red_auto = first_number(row, ["Red Auto Score"])
            blue_auto = first_number(row, ["Blue Auto Score"])

            red_teleop_total = first_number(row, ["Red Teleop Score"])
            blue_teleop_total = first_number(row, ["Blue Teleop Score"])

            red_endgame = first_number(row, ["Red Endgame Score"])
            blue_endgame = first_number(row, ["Blue Endgame Score"])

            red_foul_scored = first_number(row, ["Red Foul Score"])
            blue_foul_scored = first_number(row, ["Blue Foul Score"])
            red_foul_committed = first_number(row, ["Red Foul Committed"])
            blue_foul_committed = first_number(row, ["Blue Foul Committed"])

            red_no_penalty = None
            blue_no_penalty = None
            if red_final is not None:
                if red_foul_scored is not None:
                    red_no_penalty = red_final - red_foul_scored
                elif blue_foul_committed is not None:
                    red_no_penalty = red_final - blue_foul_committed
            if blue_final is not None:
                if blue_foul_scored is not None:
                    blue_no_penalty = blue_final - blue_foul_scored
                elif red_foul_committed is not None:
                    blue_no_penalty = blue_final - red_foul_committed

            red_teleop_only = None
            blue_teleop_only = None
            if red_teleop_total is not None and red_endgame is not None:
                red_teleop_only = red_teleop_total - red_endgame
            if blue_teleop_total is not None and blue_endgame is not None:
                blue_teleop_only = blue_teleop_total - blue_endgame

            if red_teams:
                equations.append(
                    {
                        "teams": red_teams,
                        "scores": {
                            "opr_total": red_final,
                            "opr_no_penalty": red_no_penalty,
                            "opr_auto": red_auto,
                            "opr_teleop": red_teleop_only,
                            "opr_endgame": red_endgame,
                        },
                    }
                )
            if blue_teams:
                equations.append(
                    {
                        "teams": blue_teams,
                        "scores": {
                            "opr_total": blue_final,
                            "opr_no_penalty": blue_no_penalty,
                            "opr_auto": blue_auto,
                            "opr_teleop": blue_teleop_only,
                            "opr_endgame": blue_endgame,
                        },
                    }
                )
    return equations


def build_matrices(equations):
    """Build the binary participation matrix M and score vector s for one metric."""
    team_numbers = sorted({team for eq in equations for team in eq["teams"]})
    team_index = {team: idx for idx, team in enumerate(team_numbers)}

    matrix_m = [
        [0.0 for _ in range(len(team_numbers))]
        for _ in range(len(equations))
    ]
    vector_s = [0.0 for _ in range(len(equations))]

    for row_idx, equation in enumerate(equations):
        teams = equation["teams"]
        score = equation["score"]
        for team in teams:
            matrix_m[row_idx][team_index[team]] = 1.0
        vector_s[row_idx] = score

    return team_numbers, matrix_m, vector_s


def equations_for_metric(equations, metric_key):
    metric_equations = []
    for equation in equations:
        metric_score = equation["scores"].get(metric_key)
        if metric_score is None:
            continue
        metric_equations.append({"teams": equation["teams"], "score": metric_score})
    return metric_equations


def calculate_event_opr(csv_path):
    equations = parse_match_rows(csv_path)
    if not equations:
        return None

    team_numbers = sorted({team for eq in equations for team in eq["teams"]})
    metric_vectors = {}
    matrix_m = None
    vector_s = None

    for metric_key in METRIC_ORDER:
        metric_equations = equations_for_metric(equations, metric_key)
        if not metric_equations:
            metric_vectors[metric_key] = [math.nan for _ in team_numbers]
            continue

        metric_teams, metric_m, metric_s = build_matrices(metric_equations)
        metric_team_index = {team: idx for idx, team in enumerate(metric_teams)}
        metric_opr = opr_calc(metric_m, metric_s)

        aligned_metric_opr = [math.nan for _ in team_numbers]
        for idx, team in enumerate(team_numbers):
            metric_idx = metric_team_index.get(team)
            if metric_idx is not None:
                aligned_metric_opr[idx] = metric_opr[metric_idx]

        metric_vectors[metric_key] = aligned_metric_opr

        if metric_key == "opr_total":
            matrix_m = metric_m
            vector_s = metric_s

    team_oprs = []
    for idx, team in enumerate(team_numbers):
        team_oprs.append(
            {
                "team_number": team,
                "opr_total": float(metric_vectors["opr_total"][idx]),
                "opr_no_penalty": float(metric_vectors["opr_no_penalty"][idx]),
                "opr_auto": float(metric_vectors["opr_auto"][idx]),
                "opr_teleop": float(metric_vectors["opr_teleop"][idx]),
                "opr_endgame": float(metric_vectors["opr_endgame"][idx]),
            }
        )

    team_oprs.sort(key=lambda entry: entry["opr_no_penalty"], reverse=True)

    event_code = os.path.basename(csv_path).split(" Match Details.csv")[0]
    return {
        "event_code": event_code,
        "matrix_m": matrix_m,
        "vector_s": vector_s,
        "team_oprs": team_oprs,
    }


def calculate_all_events(results_dir=RESULTS_DIR):
    csv_paths = sorted(glob.glob(os.path.join(results_dir, "*.csv")))
    all_event_results = []

    for csv_path in csv_paths:
        event_result = calculate_event_opr(csv_path)
        if event_result is not None:
            all_event_results.append(event_result)

    return all_event_results


def calculate_event_by_code(event_code, results_dir=RESULTS_DIR):
    safe_event_code = event_code.strip().upper()
    if not safe_event_code:
        return None

    csv_path = os.path.join(results_dir, f"{safe_event_code} Match Details.csv")
    if not os.path.exists(csv_path):
        return None

    return calculate_event_opr(csv_path)


def export_event_opr_csvs(event_results, export_dir=OPR_EXPORT_DIR):
    os.makedirs(export_dir, exist_ok=True)

    for event_result in event_results:
        event_code = event_result["event_code"]
        output_path = os.path.join(export_dir, f"{event_code} OPR.csv")

        with open(output_path, mode="w", encoding="utf-8-sig", newline="") as csv_file:
            writer = csv.DictWriter(
                csv_file,
                fieldnames=[
                    "Rank",
                    "Team Number",
                    "OPR",
                    "OPR No Penalty Scored",
                    "OPR Auto",
                    "OPR Teleop Only",
                    "OPR Endgame",
                ],
            )
            writer.writeheader()
            for rank, row in enumerate(event_result["team_oprs"], start=1):
                writer.writerow(
                    {
                        "Rank": rank,
                        "Team Number": row["team_number"],
                        "OPR": f"{row['opr_total']:.4f}",
                        "OPR No Penalty Scored": f"{row['opr_no_penalty']:.4f}",
                        "OPR Auto": f"{row['opr_auto']:.4f}",
                        "OPR Teleop Only": f"{row['opr_teleop']:.4f}",
                        "OPR Endgame": f"{row['opr_endgame']:.4f}",
                    }
                )


def export_single_event_opr_csv(event_result, export_dir=OPR_EXPORT_DIR):
    os.makedirs(export_dir, exist_ok=True)

    event_code = event_result["event_code"]
    output_path = os.path.join(export_dir, f"{event_code} OPR.csv")

    with open(output_path, mode="w", encoding="utf-8-sig", newline="") as csv_file:
        writer = csv.DictWriter(
            csv_file,
            fieldnames=[
                "Rank",
                "Team Number",
                "OPR",
                "npOPR",
                "Auto OPR",
                "Teleop OPR",
                "Endgame OPR",
            ],
        )
        writer.writeheader()
        for rank, row in enumerate(event_result["team_oprs"], start=1):
            writer.writerow(
                {
                    "Rank": rank,
                    "Team Number": row["team_number"],
                    "OPR": f"{row['opr_total']:.4f}",
                    "npOPR": f"{row['opr_no_penalty']:.4f}",
                    "Auto OPR": f"{row['opr_auto']:.4f}",
                    "Teleop OPR": f"{row['opr_teleop']:.4f}",
                    "Endgame OPR": f"{row['opr_endgame']:.4f}",
                }
            )

    return output_path


def generate_event_opr_csv(event_code, results_dir=RESULTS_DIR, export_dir=OPR_EXPORT_DIR):
    event_result = calculate_event_by_code(event_code, results_dir=results_dir)
    if event_result is None:
        return None

    output_path = export_single_event_opr_csv(event_result, export_dir=export_dir)
    return {
        "event_code": event_result["event_code"],
        "output_path": output_path,
        "team_count": len(event_result["team_oprs"]),
    }


if __name__ == "__main__":
    all_event_opr_results = calculate_all_events()
    export_event_opr_csvs(all_event_opr_results)

    for event_result in all_event_opr_results:
        print(f"\nEvent: {event_result['event_code']}")
        print("Top npOPRs:")
        for row in event_result["team_oprs"][:10]:
            print(
                f"Team {row['team_number']}: OPR={row['opr_total']:.2f}, "
                f"NoPenalty={row['opr_no_penalty']:.2f}, Auto={row['opr_auto']:.2f}, "
                f"TeleopOnly={row['opr_teleop']:.2f}, Endgame={row['opr_endgame']:.2f}"
            )
