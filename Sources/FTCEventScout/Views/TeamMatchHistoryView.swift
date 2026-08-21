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
            .navigationTitle("Team \(selection.teamNumber.teamNumberText) Match History")
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
                description: Text("No match history is available for Team \(teamNumber.teamNumberText) at \(eventCode).")
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

            ScoreBreakdownDisclosure(match: match)
        }
        .padding(.vertical, 8)
    }
}

private struct ScoreBreakdownDisclosure: View {
    let match: MatchRecord
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Text("Score Breakdown")
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse Score Breakdown" : "Expand Score Breakdown")

            if isExpanded {
                ScoreBreakdownGrid(match: match)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
                        .foregroundStyle(color.scoreColor)
                    if let nonPenaltyScore {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("np")
                                .foregroundStyle(.secondary)
                            Text(nonPenaltyScore, format: .number.precision(.fractionLength(0)))
                                .foregroundStyle(color.scoreColor)
                        }
                        .font(.caption.monospacedDigit())
                    }
                    Spacer()
                }

                ForEach(teams, id: \.self) { teamNumber in
                    HStack(spacing: 8) {
                        Image(systemName: teamNumber == selectedTeam ? "scope" : "circle")
                            .foregroundStyle(teamNumber == selectedTeam ? .primary : .tertiary)
                            .accessibilityHidden(true)
                        Text("Team \(teamNumber.teamNumberText)")
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
                if row.emphasized, row.id != rows.first?.id {
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                }
                GridRow {
                    Text(row.label)
                        .font(row.usesBoldValue ? .title3 : .body)
                        .fontWeight(
                            row.usesBoldValue
                                ? .bold
                                : (row.emphasized ? .semibold : .regular)
                        )
                        .padding(.leading, CGFloat(row.indent) * 14)
                    BreakdownValueView(
                        value: row.redValue,
                        alliance: .red,
                        usesDecodePatternColors: row.usesDecodePatternColors,
                        isBold: row.usesBoldValue
                    )
                    BreakdownValueView(
                        value: row.blueValue,
                        alliance: .blue,
                        usesDecodePatternColors: row.usesDecodePatternColors,
                        isBold: row.usesBoldValue
                    )
                }
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }
}

private struct BreakdownValueView: View {
    let value: String?
    let alliance: AllianceColor
    let usesDecodePatternColors: Bool
    let isBold: Bool

    var body: some View {
        Group {
            if value == nil {
                Text("—")
                    .foregroundStyle(.tertiary)
            } else {
                Text(styledValue)
            }
        }
        .font(isBold ? .title : .title3)
        .monospacedDigit()
        .fontWeight(isBold ? .bold : .regular)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel(value ?? "Unavailable")
    }

    private var styledValue: AttributedString {
        guard let value else { return AttributedString() }

        var result = AttributedString()
        for segment in ScoreBreakdownTextStyler.segments(
            in: value,
            usesDecodePatternColors: usesDecodePatternColors
        ) {
            var fragment = AttributedString(segment.text)
            switch segment.role {
            case .standard:
                break
            case .alliance:
                fragment.foregroundColor = alliance.scoreColor
            case .decodeGreen:
                fragment.foregroundColor = .green
            case .decodePurple:
                fragment.foregroundColor = .purple
            case .decodeNone:
                fragment.foregroundColor = .white
            }
            result.append(fragment)
        }
        return result
    }
}

struct BreakdownRow: Identifiable {
    let id: String
    let label: String
    let redValue: String?
    let blueValue: String?
    let indent: Int
    let emphasized: Bool

    var usesDecodePatternColors: Bool {
        id == "auto-classifier" || id == "teleop-classifier"
    }

    var usesBoldValue: Bool {
        switch id {
        case "total-auto", "total-teleop", "penalty", "final": true
        default: false
        }
    }

    static func rows(for match: MatchRecord) -> [BreakdownRow] {
        let redByID = Dictionary(uniqueKeysWithValues: match.redScore.details.map { ($0.id, $0) })
        let blueByID = Dictionary(uniqueKeysWithValues: match.blueScore.details.map { ($0.id, $0) })
        var identifiers = match.redScore.details.map(\.id)
        identifiers.append(contentsOf: match.blueScore.details.map(\.id).filter {
            !redByID.keys.contains($0)
        })

        var rows: [BreakdownRow] = identifiers.compactMap { identifier in
            let red = redByID[identifier]
            let blue = blueByID[identifier]
            guard let template = red ?? blue else { return nil }
            return BreakdownRow(
                id: identifier,
                label: template.label,
                redValue: displayValue(red?.value, for: identifier),
                blueValue: displayValue(blue?.value, for: identifier),
                indent: template.indent,
                emphasized: template.emphasized
            )
        }

        rows.removeAll { $0.id == "total-auto" || $0.id == "total-teleop" }

        let totalAuto = BreakdownRow(
            id: "total-auto",
            label: "Total Auto Points",
            redValue: displayScore(match.redScore.autoScore),
            blueValue: displayScore(match.blueScore.autoScore),
            indent: 1,
            emphasized: false
        )
        let autoInsertionIndex = rows.lastIndex { $0.id.hasPrefix("auto") }
            .map { rows.index(after: $0) } ?? rows.startIndex
        rows.insert(totalAuto, at: autoInsertionIndex)

        let totalTeleop = BreakdownRow(
            id: "total-teleop",
            label: "Total Teleop Points",
            redValue: displayScore(match.redScore.teleopScore),
            blueValue: displayScore(match.blueScore.teleopScore),
            indent: 1,
            emphasized: false
        )
        let teleopInsertionIndex = rows.firstIndex {
            $0.id.hasPrefix("penalty") || $0.id == "final"
        } ?? rows.endIndex
        rows.insert(totalTeleop, at: teleopInsertionIndex)

        return rows
    }

    private static func displayScore(_ value: Double?) -> String? {
        guard let value else { return nil }
        if value.rounded() == value {
            return String(Int(value))
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func displayValue(_ value: String?, for identifier: String) -> String? {
        guard let value,
              identifier == "auto-classifier" || identifier == "teleop-classifier" else {
            return value
        }

        let abbreviations = [
            "green": "G",
            "purple": "P",
            "none": "N",
        ]
        return value
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                let state = component.trimmingCharacters(in: .whitespacesAndNewlines)
                return abbreviations[state.lowercased()] ?? state
            }
            .joined(separator: " / ")
    }
}

private extension AllianceColor {
    var scoreColor: Color {
        self == .red ? .red : .blue
    }
}
