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

/// Red and blue values flank a center line, like the two halves of the field. On rows where
/// both values are single numbers, a bar grows from the line toward each alliance, scaled
/// to the row's larger value, so the winner of each category reads without the numbers.
private struct ScoreBreakdownGrid: View {
    let rows: [BreakdownRow]
    /// Zebra stripes alternate within each section and restart after every header or total.
    let stripes: [Bool]

    init(match: MatchRecord) {
        rows = BreakdownRow.rows(for: match)
        var stripes: [Bool] = []
        var detailIndex = 0
        for row in rows {
            if BreakdownRowStyle(row) == .detail {
                stripes.append(!detailIndex.isMultiple(of: 2))
                detailIndex += 1
            } else {
                stripes.append(false)
                detailIndex = 0
            }
        }
        self.stripes = stripes
    }

    var body: some View {
        VStack(spacing: 0) {
            BreakdownHeaderView()
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                BreakdownRowView(row: row, isStriped: stripes[index], isFirst: index == 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: 640)
    }
}

private enum BreakdownMetrics {
    static let horizontalPadding: CGFloat = 12
    static let valueWidth: CGFloat = 120
    static let barWidth: CGFloat = 96
    static let barGap: CGFloat = 10

    /// Distance from a row's trailing edge to the center line.
    static var centerLineInset: CGFloat {
        horizontalPadding + valueWidth + barGap + barWidth / 2
    }
}

/// The role a row plays in the score sheet, which sets its type size, spacing, and rules.
private enum BreakdownRowStyle {
    /// A scoring period or penalty group that heads its line items.
    case section
    case detail
    /// A period total, set off by a single rule above it.
    case subtotal
    /// The final score, set off by a double rule above it.
    case total

    init(_ row: BreakdownRow) {
        if row.id == "final" {
            self = .total
        } else if row.usesBoldValue, !row.emphasized {
            self = .subtotal
        } else {
            self = row.emphasized ? .section : .detail
        }
    }

    var labelFont: Font {
        switch self {
        case .detail: .system(size: 13)
        case .section, .subtotal: .system(size: 13, weight: .semibold)
        case .total: .system(size: 15, weight: .bold)
        }
    }

    var valueSize: CGFloat {
        switch self {
        case .detail: 14
        case .section, .subtotal: 15
        case .total: 22
        }
    }

    /// The higher value sits one weight step above the other.
    func valueWeight(isHigher: Bool) -> Font.Weight {
        switch self {
        case .detail: isHigher ? .semibold : .regular
        case .section, .subtotal, .total: isHigher ? .bold : .medium
        }
    }

    var barHeight: CGFloat {
        switch self {
        case .detail: 3
        case .section, .subtotal: 4
        case .total: 6
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .detail: 4
        case .section, .subtotal: 6
        case .total: 9
        }
    }
}

private struct BreakdownHeaderView: View {
    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("Red")
                .foregroundStyle(AllianceColor.red.displayColor)
                .frame(width: BreakdownMetrics.valueWidth, alignment: .trailing)
            Color.clear
                .frame(width: BreakdownMetrics.barWidth, height: 1)
                .padding(.horizontal, BreakdownMetrics.barGap)
            Text("Blue")
                .foregroundStyle(AllianceColor.blue.displayColor)
                .frame(width: BreakdownMetrics.valueWidth, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, BreakdownMetrics.horizontalPadding)
        .padding(.bottom, 6)
        .background(alignment: .trailing) { BreakdownCenterLine() }
        .accessibilityHidden(true)
    }
}

private struct BreakdownCenterLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1)
            .padding(.trailing, BreakdownMetrics.centerLineInset - 0.5)
    }
}

private struct BreakdownRowView: View {
    let row: BreakdownRow
    let isStriped: Bool
    let isFirst: Bool

    private var style: BreakdownRowStyle { BreakdownRowStyle(row) }

    var body: some View {
        let leader = row.leadingAlliance
        HStack(spacing: 0) {
            Text(row.label)
                .font(style.labelFont)
                .lineLimit(2)
                .padding(.leading, CGFloat(row.indent) * 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            BreakdownValueView(
                value: row.redValue,
                alliance: .red,
                row: row,
                style: style,
                comparison: .init(alliance: .red, leader: leader)
            )
            .frame(width: BreakdownMetrics.valueWidth, alignment: .trailing)
            BreakdownMarginBar(values: row.numericValues, height: style.barHeight)
                .padding(.horizontal, BreakdownMetrics.barGap)
            BreakdownValueView(
                value: row.blueValue,
                alliance: .blue,
                row: row,
                style: style,
                comparison: .init(alliance: .blue, leader: leader)
            )
            .frame(width: BreakdownMetrics.valueWidth, alignment: .leading)
        }
        .padding(.horizontal, BreakdownMetrics.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .overlay(alignment: .top) { rule }
        .padding(.top, topSpacing)
        .background(alignment: .trailing) { BreakdownCenterLine() }
        .background(isStriped ? AnyShapeStyle(.scoutZebra) : AnyShapeStyle(.clear))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.label)
        .accessibilityValue(accessibilityValue(leader: leader))
    }

    /// Sections open with a gap; totals take the rule-above-the-sum of a paper score sheet.
    private var topSpacing: CGFloat {
        guard !isFirst else { return 0 }
        switch style {
        case .section: return 10
        case .total: return 6
        case .detail, .subtotal: return 0
        }
    }

    @ViewBuilder
    private var rule: some View {
        switch style {
        case .subtotal:
            Rectangle()
                .fill(.scoutSeparator)
                .frame(height: 1)
        case .total:
            VStack(spacing: 2) {
                Rectangle().frame(height: 1)
                Rectangle().frame(height: 1)
            }
            .foregroundStyle(.scoutSeparator)
        case .section, .detail:
            EmptyView()
        }
    }

    private func accessibilityValue(leader: AllianceColor?) -> String {
        let red = BreakdownValueView.spokenValue(row.redValue, row: row)
        let blue = BreakdownValueView.spokenValue(row.blueValue, row: row)
        var summary = "Red \(red), Blue \(blue)"
        if let leader {
            summary += ", \(leader == .red ? "Red" : "Blue") higher"
        }
        return summary
    }
}

/// Bars grow outward from the center line, each scaled to the larger of the two values.
private struct BreakdownMarginBar: View {
    let values: (red: Double, blue: Double)?
    let height: CGFloat

    private var halfWidth: CGFloat { BreakdownMetrics.barWidth / 2 }

    var body: some View {
        HStack(spacing: 1) {
            side(.red)
                .frame(width: halfWidth - 0.5, alignment: .trailing)
            side(.blue)
                .frame(width: halfWidth - 0.5, alignment: .leading)
        }
        .frame(width: BreakdownMetrics.barWidth, height: height)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func side(_ alliance: AllianceColor) -> some View {
        if let length = length(for: alliance) {
            // Flat against the center line, rounded at the tip.
            let radius = height / 2
            UnevenRoundedRectangle(
                topLeadingRadius: alliance == .red ? radius : 0,
                bottomLeadingRadius: alliance == .red ? radius : 0,
                bottomTrailingRadius: alliance == .blue ? radius : 0,
                topTrailingRadius: alliance == .blue ? radius : 0
            )
            .fill(alliance.displayColor)
            .frame(width: length)
        } else {
            Color.clear
        }
    }

    private func length(for alliance: AllianceColor) -> CGFloat? {
        guard let values else { return nil }
        let largest = max(values.red, values.blue)
        let value = alliance == .red ? values.red : values.blue
        guard largest > 0, value > 0 else { return nil }
        return max((halfWidth - 0.5) * CGFloat(value / largest), height)
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
    let row: BreakdownRow
    let style: BreakdownRowStyle
    let comparison: BreakdownComparison

    private var textAlignment: TextAlignment {
        alliance == .red ? .trailing : .leading
    }

    var body: some View {
        Group {
            if let value {
                if let artifacts = Self.classifierArtifacts(value, row: row) {
                    ClassifierArtifactsView(artifacts: artifacts)
                } else if value.trimmingCharacters(in: .whitespaces) == "0" {
                    // Zeros recede so the categories that scored stand out.
                    Text(value)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(styledValue(value))
                }
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(
            size: style.valueSize,
            weight: style.valueWeight(isHigher: comparison == .higher),
            design: .rounded
        ).monospacedDigit())
        .lineLimit(row.valueLineLimit)
        .minimumScaleFactor(0.75)
        .multilineTextAlignment(textAlignment)
        .fixedSize(horizontal: false, vertical: row.valueLineLimit == nil)
    }

    private func styledValue(_ value: String) -> AttributedString {
        var result = AttributedString()
        for segment in ScoreBreakdownTextStyler.segments(
            in: value,
            usesDecodePatternColors: false
        ) {
            var fragment = AttributedString(segment.text)
            if segment.role == .alliance {
                fragment.foregroundColor = alliance.displayColor
            }
            result.append(fragment)
        }
        return result
    }

    /// The DECODE classifier's slots, or nil when the row isn't a classifier state
    /// or holds anything other than green, purple, and empty slots.
    static func classifierArtifacts(_ value: String, row: BreakdownRow) -> [ClassifierArtifact]? {
        guard row.usesDecodePatternColors else { return nil }
        let artifacts = value
            .split(separator: "/")
            .map { ClassifierArtifact(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        guard !artifacts.isEmpty, !artifacts.contains(nil) else { return nil }
        return artifacts.compactMap { $0 }
    }

    static func spokenValue(_ value: String?, row: BreakdownRow) -> String {
        guard let value else { return "unavailable" }
        if let artifacts = classifierArtifacts(value, row: row) {
            return artifacts.map(\.spokenName).joined(separator: ", ")
        }
        return value
    }
}

private enum ClassifierArtifact: String {
    case green = "G"
    case purple = "P"
    case empty = "N"

    var spokenName: String {
        switch self {
        case .green: "green"
        case .purple: "purple"
        case .empty: "empty"
        }
    }
}

/// The classifier's artifacts drawn as balls, grouped in threes to read against the motif.
private struct ClassifierArtifactsView: View {
    let artifacts: [ClassifierArtifact]

    private var groups: [ArraySlice<ClassifierArtifact>] {
        stride(from: 0, to: artifacts.count, by: 3).map {
            artifacts[$0..<min($0 + 3, artifacts.count)]
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                HStack(spacing: 3) {
                    ForEach(Array(group.enumerated()), id: \.offset) { _, artifact in
                        ball(artifact)
                    }
                }
            }
        }
        .frame(height: 16)
    }

    @ViewBuilder
    private func ball(_ artifact: ClassifierArtifact) -> some View {
        switch artifact {
        case .green:
            Circle().fill(Color.green).frame(width: 10, height: 10)
        case .purple:
            Circle().fill(Color.purple).frame(width: 10, height: 10)
        case .empty:
            Circle().strokeBorder(.tertiary, lineWidth: 1).frame(width: 10, height: 10)
        }
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
        guard let values = numericValues, values.red != values.blue else {
            return nil
        }
        return values.red > values.blue ? .red : .blue
    }

    /// Both alliances' values when each is a single number.
    var numericValues: (red: Double, blue: Double)? {
        guard let red = Self.numericValue(redValue),
              let blue = Self.numericValue(blueValue) else {
            return nil
        }
        return (red, blue)
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

