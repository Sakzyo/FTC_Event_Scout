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
                matches: model.matches(for: selection.teamNumber),
                metric: model.currentEvent?.oprcAnalysis.teamMetrics[selection.teamNumber],
                analysis: model.currentEvent?.oprcAnalysis
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
    let metric: TeamOPRcMetric?
    let analysis: OPRcAnalysis?

    var body: some View {
        if matches.isEmpty, metric == nil {
            ContentUnavailableView(
                "No Matches Found",
                systemImage: "rectangle.stack",
                description: Text("No match history is available for Team \(teamNumber.teamNumberText) at \(eventCode).")
            )
        } else {
            List {
                if let metric {
                    Section("Offensive Power · Scouting Estimates") {
                        TeamOPRcSummaryView(metric: metric, analysis: analysis)
                    }
                }

                Section {
                    if matches.isEmpty {
                        Text("No match records are available for this team.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(matches) { match in
                            MatchCardView(
                                model: model,
                                eventCode: eventCode,
                                selectedTeam: teamNumber,
                                match: match
                            )
                        }
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(matches.count) matches at \(eventCode)")
                        Spacer()
                        if !matches.isEmpty {
                            MatchRecordSummary(matches: matches, teamNumber: teamNumber)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct TeamOPRcSummaryView: View {
    let metric: TeamOPRcMetric
    let analysis: OPRcAnalysis?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 24) {
                MetricValue(title: "OPR", value: metric.opr)
                MetricValue(title: "OPRc", value: metric.oprc)
                MetricCount(title: "Matches used", value: metric.matchesUsed)
                MetricCount(
                    title: "Outliers removed",
                    value: metric.matchesExcludedAsOutliers
                )
                Spacer(minLength: 0)
            }

            Text("OPRc is a scouting prediction metric, not an official FTC ranking.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let bounds = analysis?.residualBounds {
                DisclosureGroup("Residual IQR details") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                        diagnosticRow("Q1", value: bounds.firstQuartile)
                        diagnosticRow("Q3", value: bounds.thirdQuartile)
                        diagnosticRow("IQR", value: bounds.interquartileRange)
                        diagnosticRow("Lower threshold", value: bounds.lowerBound)
                        diagnosticRow("Upper threshold", value: bounds.upperBound)
                    }
                    .padding(.top, 6)
                }
                .font(.callout)
            } else {
                Text("IQR filtering was not applied because fewer than four valid alliance observations were available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    private func diagnosticRow(_ label: String, value: Double) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value, format: .number.precision(.fractionLength(2)))
                .monospacedDigit()
        }
    }
}

private struct MetricValue: View {
    let title: String
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            NumericValueView(value: value, fractionDigits: 2)
                .font(.title2.monospacedDigit().weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MetricCount: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(.title2.monospacedDigit().weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MatchRecordSummary: View {
    let wins: Int
    let losses: Int
    let ties: Int

    init(matches: [MatchRecord], teamNumber: Int) {
        let outcomes = matches.map { $0.outcome(for: teamNumber) }
        wins = outcomes.filter { $0 == .win }.count
        losses = outcomes.filter { $0 == .loss }.count
        ties = outcomes.filter { $0 == .tie }.count
    }

    var body: some View {
        HStack(spacing: 10) {
            count(wins, label: "W", color: .green)
            count(losses, label: "L", color: .red)
            count(ties, label: "T", color: .orange)
        }
        .font(.callout.monospacedDigit().weight(.semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Record: \(wins) wins, \(losses) losses, \(ties) ties")
    }

    private func count(_ value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(value.formatted())
                .foregroundStyle(value > 0 ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
            Text(label)
                .foregroundStyle(.secondary)
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
            HStack(alignment: .center) {
                Text(match.displayTitle)
                    .font(.headline)
                Spacer()
                MatchOutcomeView(outcome: match.outcome(for: selectedTeam))
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach([AllianceColor.red, .blue], id: \.self) { alliance in
                    AlliancePanelView(
                        model: model,
                        eventCode: eventCode,
                        selectedTeam: selectedTeam,
                        color: alliance,
                        teams: alliance == .red ? match.redTeams : match.blueTeams,
                        score: alliance == .red
                            ? match.redScore.finalScore
                            : match.blueScore.finalScore,
                        nonPenaltyScore: match.nonPenaltyScore(for: alliance),
                        result: match.result(for: alliance)
                    )
                }
            }

            ScoreBreakdownDisclosure(match: match)
        }
        .padding(.vertical, 8)
    }
}

private struct ScoreBreakdownDisclosure: View {
    let match: MatchRecord
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
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
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .offset(y: -6))
                    )
            }
        }
    }
}

private struct MatchOutcomeView: View {
    let outcome: MatchOutcome

    var body: some View {
        switch outcome {
        case .win:
            StatusPill(title: "Win", systemImage: "checkmark.circle.fill", tint: .green)
        case .loss:
            StatusPill(title: "Loss", systemImage: "xmark.circle.fill", tint: .red)
        case .tie:
            StatusPill(title: "Tie", systemImage: "equal.circle.fill", tint: .orange)
        case .unavailable:
            Label("Unavailable", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}

private enum AllianceResult {
    case won
    case lost
    case tied
    case unavailable
}

private extension MatchRecord {
    func result(for alliance: AllianceColor) -> AllianceResult {
        guard let red = redScore.finalScore, let blue = blueScore.finalScore else {
            return .unavailable
        }
        if red == blue { return .tied }
        return (red > blue) == (alliance == .red) ? .won : .lost
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
    let result: AllianceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(color.displayName, systemImage: "circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color.displayColor)
                Spacer()
                if result == .won {
                    Label("Winner", systemImage: "trophy.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color.displayColor)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                NumericValueView(value: score, fractionDigits: 0)
                    .font(.system(.largeTitle, design: .rounded, weight: result == .won ? .bold : .medium))
                    .foregroundStyle(color.displayColor)
                    .opacity(result == .lost ? 0.65 : 1)
                if let nonPenaltyScore {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(nonPenaltyScore, format: .number.precision(.fractionLength(0)))
                            .monospacedDigit()
                        Text("without penalties")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(teams, id: \.self) { teamNumber in
                    let isSelected = teamNumber == selectedTeam
                    HStack(spacing: 8) {
                        Image(systemName: isSelected ? "scope" : "circle")
                            .foregroundStyle(isSelected ? AnyShapeStyle(color.displayColor) : AnyShapeStyle(.tertiary))
                            .accessibilityHidden(true)
                        Text("Team \(teamNumber.teamNumberText)")
                            .monospacedDigit()
                            .fontWeight(isSelected ? .semibold : .regular)
                        TeamTagsSummaryView(
                            tags: model.tags(eventCode: eventCode, teamNumber: teamNumber)
                        )
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .alliancePanelBackground(color, outlined: teams.contains(selectedTeam))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        switch result {
        case .won: "\(color.displayName), winner"
        case .lost: "\(color.displayName), lost"
        case .tied: "\(color.displayName), tied"
        case .unavailable: color.displayName
        }
    }
}

private struct ScoreBreakdownGrid: View {
    let rows: [BreakdownRow]

    init(match: MatchRecord) {
        rows = BreakdownRow.rows(for: match)
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text("Category")
                    .breakdownCell(alignment: .leading)
                Text("Red")
                    .foregroundStyle(.red)
                    .breakdownCell(alignment: .trailing)
                    .gridColumnAlignment(.trailing)
                Text("Blue")
                    .foregroundStyle(.blue)
                    .breakdownCell(alignment: .trailing)
                    .gridColumnAlignment(.trailing)
            }
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)

            Divider()
                .gridCellUnsizedAxes(.horizontal)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if row.emphasized, index != 0 {
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                }
                let isStriped = index.isMultiple(of: 2)
                let leader = row.leadingAlliance
                GridRow {
                    Text(row.label)
                        .font(row.usesBoldValue ? .title3 : .body)
                        .fontWeight(
                            row.usesBoldValue
                                ? .bold
                                : (row.emphasized ? .semibold : .regular)
                        )
                        .padding(.leading, CGFloat(row.indent) * 14)
                        .breakdownCell(alignment: .leading, isStriped: isStriped)
                    BreakdownValueView(
                        value: row.redValue,
                        alliance: .red,
                        usesDecodePatternColors: row.usesDecodePatternColors,
                        lineLimit: row.valueLineLimit,
                        isBold: row.usesBoldValue,
                        comparison: .init(alliance: .red, leader: leader)
                    )
                    .breakdownCell(alignment: .trailing, isStriped: isStriped)
                    BreakdownValueView(
                        value: row.blueValue,
                        alliance: .blue,
                        usesDecodePatternColors: row.usesDecodePatternColors,
                        lineLimit: row.valueLineLimit,
                        isBold: row.usesBoldValue,
                        comparison: .init(alliance: .blue, leader: leader)
                    )
                    .breakdownCell(alignment: .trailing, isStriped: isStriped)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: 680, alignment: .leading)
    }
}

private extension View {
    /// Pads a breakdown cell and fills its whole grid cell so zebra stripes form continuous rows.
    func breakdownCell(alignment: Alignment, isStriped: Bool = false) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(isStriped ? Color.primary.opacity(0.05) : Color.clear)
    }
}

/// How one alliance's value compares with the other alliance's value in the same row.
private enum BreakdownComparison {
    case higher
    case lower
    case even

    init(alliance: AllianceColor, leader: AllianceColor?) {
        guard let leader else {
            self = .even
            return
        }
        self = leader == alliance ? .higher : .lower
    }
}

private struct BreakdownValueView: View {
    let value: String?
    let alliance: AllianceColor
    let usesDecodePatternColors: Bool
    let lineLimit: Int?
    let isBold: Bool
    let comparison: BreakdownComparison

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
        .fontWeight(fontWeight)
        .opacity(comparison == .lower ? 0.6 : 1)
        .lineLimit(lineLimit)
        .minimumScaleFactor(0.75)
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: lineLimit == nil)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel(value ?? "Unavailable")
        .accessibilityValue(comparison == .higher ? "Higher" : "")
    }

    private var fontWeight: Font.Weight {
        if isBold { return .bold }
        return comparison == .higher ? .semibold : .regular
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
                fragment.foregroundColor = alliance.displayColor
            case .decodeGreen:
                fragment.foregroundColor = .green
            case .decodePurple:
                fragment.foregroundColor = .purple
            case .decodeNone:
                fragment.foregroundColor = .primary
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

    var valueLineLimit: Int? {
        switch id {
        case "teleop-flower-red", "teleop-flower-scoring", "teleop-flower-blue", "teleop-flower-audience": nil
        default: 1
        }
    }

    /// The alliance with the strictly higher single numeric value in this row, if any.
    /// Multi-part values such as "3 / 2" or location names are never compared.
    var leadingAlliance: AllianceColor? {
        guard let red = Self.numericValue(redValue),
              let blue = Self.numericValue(blueValue),
              red != blue else {
            return nil
        }
        return red > blue ? .red : .blue
    }

    private static func numericValue(_ value: String?) -> Double? {
        guard let value,
              let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              number.isFinite else {
            return nil
        }
        return number
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
