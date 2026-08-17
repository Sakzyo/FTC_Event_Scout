import SwiftUI

struct TeamMatchHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel
    let selection: TeamSelection

    var body: some View {
        NavigationStack {
            MatchHistoryContent(
                model: model,
                eventCode: selection.eventCode,
                teamNumber: selection.teamNumber,
                matches: model.matches(for: selection.teamNumber)
            )
            .navigationTitle("Team \(selection.teamNumber) Match History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 620)
    }
}

private struct MatchHistoryContent: View {
    @Bindable var model: AppModel
    let eventCode: String
    let teamNumber: Int
    let matches: [MatchRecord]

    var body: some View {
        if matches.isEmpty {
            ContentUnavailableView(
                "No Matches Found",
                systemImage: "rectangle.stack",
                description: Text("No match history is available for Team \(teamNumber) at \(eventCode).")
            )
        } else {
            List {
                Section {
                    ForEach(matches) { match in
                        MatchCardView(
                            model: model,
                            eventCode: eventCode,
                            selectedTeam: teamNumber,
                            match: match
                        )
                    }
                } header: {
                    Text("\(matches.count) matches at \(eventCode)")
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct MatchCardView: View {
    @Bindable var model: AppModel
    let eventCode: String
    let selectedTeam: Int
    let match: MatchRecord
    @State private var showsBreakdown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(match.displayTitle)
                    .font(.headline)
                Spacer()
                MatchOutcomeView(outcome: match.outcome(for: selectedTeam))
            }

            HStack(alignment: .top, spacing: 12) {
                AlliancePanelView(
                    model: model,
                    eventCode: eventCode,
                    selectedTeam: selectedTeam,
                    color: .red,
                    teams: match.redTeams,
                    score: match.redScore.finalScore,
                    nonPenaltyScore: match.nonPenaltyScore(for: .red)
                )
                AlliancePanelView(
                    model: model,
                    eventCode: eventCode,
                    selectedTeam: selectedTeam,
                    color: .blue,
                    teams: match.blueTeams,
                    score: match.blueScore.finalScore,
                    nonPenaltyScore: match.nonPenaltyScore(for: .blue)
                )
            }

            DisclosureGroup("Score Breakdown", isExpanded: $showsBreakdown) {
                ScoreBreakdownGrid(match: match)
                    .padding(.top, 8)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct MatchOutcomeView: View {
    let outcome: MatchOutcome

    var body: some View {
        switch outcome {
        case .win:
            Label("Win", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .loss:
            Label("Loss", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .tie:
            Label("Tie", systemImage: "equal.circle.fill")
                .foregroundStyle(.orange)
        case .unavailable:
            Label("Unavailable", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}

private struct AlliancePanelView: View {
    @Bindable var model: AppModel
    let eventCode: String
    let selectedTeam: Int
    let color: AllianceColor
    let teams: [Int]
    let score: Double?
    let nonPenaltyScore: Double?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    NumericValueView(value: score, fractionDigits: 0)
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                    if let nonPenaltyScore {
                        Text("np \(nonPenaltyScore, format: .number.precision(.fractionLength(0)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                ForEach(teams, id: \.self) { teamNumber in
                    HStack(spacing: 8) {
                        Image(systemName: teamNumber == selectedTeam ? "scope" : "circle")
                            .foregroundStyle(teamNumber == selectedTeam ? .primary : .tertiary)
                            .accessibilityHidden(true)
                        Text("Team \(teamNumber)")
                            .fontWeight(teamNumber == selectedTeam ? .semibold : .regular)
                        TeamTagsSummaryView(
                            tags: model.tags(eventCode: eventCode, teamNumber: teamNumber)
                        )
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(3)
        } label: {
            Label(
                color == .red ? "Red Alliance" : "Blue Alliance",
                systemImage: "circle.fill"
            )
            .foregroundStyle(color == .red ? .red : .blue)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ScoreBreakdownGrid: View {
    let rows: [BreakdownRow]

    init(match: MatchRecord) {
        rows = BreakdownRow.rows(for: match)
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
            GridRow {
                Text("Category")
                    .font(.caption.weight(.semibold))
                Text("Red")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .gridColumnAlignment(.trailing)
                Text("Blue")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .gridColumnAlignment(.trailing)
            }
            Divider()
                .gridCellUnsizedAxes(.horizontal)
            ForEach(rows) { row in
                GridRow {
                    Text(row.label)
                        .fontWeight(row.emphasized ? .semibold : .regular)
                    NumericValueView(value: row.redValue, fractionDigits: 0)
                    NumericValueView(value: row.blueValue, fractionDigits: 0)
                }
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
    }
}

private struct BreakdownRow: Identifiable {
    let id: String
    let label: String
    let redValue: Double?
    let blueValue: Double?
    let emphasized: Bool

    static func rows(for match: MatchRecord) -> [BreakdownRow] {
        let red = match.redScore
        let blue = match.blueScore
        var rows = [
            BreakdownRow(id: "auto", label: "Auto", redValue: red.autoScore, blueValue: blue.autoScore, emphasized: true),
            BreakdownRow(id: "auto-leave", label: "  Leave Points", redValue: red.autoLeavePoints, blueValue: blue.autoLeavePoints, emphasized: false),
            BreakdownRow(id: "auto-artifacts", label: "  Artifact Points", redValue: red.autoArtifactPoints, blueValue: blue.autoArtifactPoints, emphasized: false),
        ]
        if red.autoClassifiedArtifacts != nil || blue.autoClassifiedArtifacts != nil {
            rows.append(BreakdownRow(id: "auto-classified", label: "    Classified", redValue: red.autoClassifiedArtifacts, blueValue: blue.autoClassifiedArtifacts, emphasized: false))
        }
        if red.autoOverflowArtifacts != nil || blue.autoOverflowArtifacts != nil {
            rows.append(BreakdownRow(id: "auto-overflow", label: "    Overflow", redValue: red.autoOverflowArtifacts, blueValue: blue.autoOverflowArtifacts, emphasized: false))
        }
        rows.append(contentsOf: [
            BreakdownRow(id: "auto-pattern", label: "  Pattern", redValue: red.autoPatternPoints, blueValue: blue.autoPatternPoints, emphasized: false),
            BreakdownRow(id: "teleop", label: "Driver Controlled", redValue: red.teleopScore, blueValue: blue.teleopScore, emphasized: true),
            BreakdownRow(id: "endgame", label: "  Base Points", redValue: red.endgameScore, blueValue: blue.endgameScore, emphasized: false),
            BreakdownRow(id: "teleop-artifacts", label: "  Artifact Points", redValue: red.teleopArtifactPoints, blueValue: blue.teleopArtifactPoints, emphasized: false),
        ])
        if red.teleopClassifiedArtifacts != nil || blue.teleopClassifiedArtifacts != nil {
            rows.append(BreakdownRow(id: "teleop-classified", label: "    Classified", redValue: red.teleopClassifiedArtifacts, blueValue: blue.teleopClassifiedArtifacts, emphasized: false))
        }
        if red.teleopOverflowArtifacts != nil || blue.teleopOverflowArtifacts != nil {
            rows.append(BreakdownRow(id: "teleop-overflow", label: "    Overflow", redValue: red.teleopOverflowArtifacts, blueValue: blue.teleopOverflowArtifacts, emphasized: false))
        }
        rows.append(contentsOf: [
            BreakdownRow(id: "teleop-pattern", label: "  Pattern", redValue: red.teleopPatternPoints, blueValue: blue.teleopPatternPoints, emphasized: false),
            BreakdownRow(id: "depot", label: "  Depot", redValue: red.teleopDepotPoints, blueValue: blue.teleopDepotPoints, emphasized: false),
            BreakdownRow(id: "penalty", label: "Penalty Points Awarded", redValue: blue.foulCommitted, blueValue: red.foulCommitted, emphasized: true),
            BreakdownRow(id: "major", label: "  Major Fouls", redValue: red.majorFouls, blueValue: blue.majorFouls, emphasized: false),
            BreakdownRow(id: "minor", label: "  Minor Fouls", redValue: red.minorFouls, blueValue: blue.minorFouls, emphasized: false),
            BreakdownRow(id: "final", label: "Final Score", redValue: red.finalScore, blueValue: blue.finalScore, emphasized: true),
        ])
        return rows
    }
}
