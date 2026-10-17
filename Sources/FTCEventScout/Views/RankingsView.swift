import Charts
import SwiftUI

struct RankingsView: View {
    @Bindable var model: AppModel
    let event: EventData
    let present: (RankingPresentation) -> Void

    var body: some View {
        VStack(spacing: 0) {
            RankingsControls(model: model)
            Divider()

            HStack(spacing: 0) {
                switch event.mode {
                case .live:
                    LiveRankingsTable(
                        model: model,
                        rows: model.rankedStandings,
                        eventCode: event.eventCode,
                        teamMetrics: event.oprcAnalysis.teamMetrics,
                        present: present
                    )
                case .preview:
                    PreviewRankingsTable(
                        model: model,
                        rows: model.rankedStandings,
                        eventCode: event.eventCode,
                        season: event.season,
                        present: present
                    )
                }

                Divider()

                OPRChartsPanel(
                    mode: event.mode,
                    series: event.oprChartSeries,
                    layout: model.oprChartLayout,
                    showFullChart: { present(.chart($0)) }
                )
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            }
        }
    }
}

private struct OPRChartsPanel: View {
    let mode: EventMode
    let series: [OPRChartSeries]
    let layout: OPRChartLayout
    let showFullChart: (OPRChartSeries) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "OPR LEADERS")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .accessibilityLabel("Compare OPR Leaders")
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if mode == .live {
                    HUDLabel(layout == .stacked ? "TOP 10 · CLICK TO EXPAND" : "ALL TEAMS")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if mode == .preview {
                ContentUnavailableView {
                    Label("OPR Charts Unavailable", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("Historical previews do not include live OPR, npOPR, teleop, auto, or endgame estimates.")
                }
            } else if series.allSatisfy({ $0.entries.isEmpty }) {
                ContentUnavailableView {
                    Label("No OPR Data", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("OPR charts will appear when team estimates are available.")
                }
            } else {
                switch layout {
                case .stacked:
                    OPRStackedLeaders(series: series, showFullChart: showFullChart)
                case .focused:
                    OPRFocusedLeaders(series: series)
                }
            }
        }
        .background(.background)
    }
}

/// Every metric at once: a compact top-10 card per metric, each opening the full chart.
private struct OPRStackedLeaders: View {
    let series: [OPRChartSeries]
    let showFullChart: (OPRChartSeries) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(series) { metricSeries in
                    OPRMetricChartButton(
                        series: metricSeries,
                        showFullChart: { showFullChart(metricSeries) }
                    )
                }
            }
            .padding(12)
        }
    }
}

private struct OPRMetricChartButton: View {
    let series: OPRChartSeries
    let showFullChart: () -> Void

    var body: some View {
        Button(action: showFullChart) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: series.metric.title)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                    Spacer()
                    HUDLabel(teamCountLabel)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }

                if series.summaryEntries.isEmpty {
                    Text("No values available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    OPRBarChart(
                        metric: series.metric,
                        entries: series.summaryEntries,
                        valueDomain: series.summaryValueDomain,
                        teamDomain: series.summaryTeamDomain,
                        rowHeight: 21,
                        minimumHeight: 104,
                        desiredTickCount: 3
                    )
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(HUDCardButtonStyle())
        .disabled(series.summaryEntries.isEmpty)
        .help("Show all teams for \(series.metric.title)")
        .accessibilityLabel("\(series.metric.accessibilityTitle) chart")
        .accessibilityValue(accessibilityCountLabel)
        .accessibilityHint("Open a larger chart containing every team with an available value.")
    }

    private var teamCountLabel: String {
        if series.availableTeamCount > series.summaryEntries.count {
            return "TOP \(series.summaryEntries.count)/\(series.availableTeamCount)"
        }
        return "\(series.summaryEntries.count) TEAMS"
    }

    private var accessibilityCountLabel: String {
        if series.availableTeamCount > series.summaryEntries.count {
            return "Top \(series.summaryEntries.count) of \(series.availableTeamCount)"
        }
        return "\(series.summaryEntries.count) teams"
    }
}

/// One metric at a time: a segmented switcher, a leader readout, and every team's bar.
private struct OPRFocusedLeaders: View {
    let series: [OPRChartSeries]
    @SceneStorage("focusedOPRMetric") private var selectedMetricRaw = OPRChartMetric.nonPenalty.rawValue

    private var selectedSeries: OPRChartSeries? {
        series.first { $0.metric.rawValue == selectedMetricRaw } ?? series.first
    }

    private var selection: Binding<OPRChartMetric> {
        Binding {
            selectedSeries?.metric ?? .nonPenalty
        } set: { metric in
            selectedMetricRaw = metric.rawValue
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HUDSegmentedControl(
                accessibilityTitle: "OPR metric",
                options: series.map(\.metric),
                selection: selection,
                title: \.shortTitle
            )
            .padding([.horizontal, .top], 12)

            if let current = selectedSeries {
                VStack(spacing: 0) {
                    OPRLeaderReadout(series: current)
                        .padding(12)

                    if current.entries.isEmpty {
                        ContentUnavailableView(
                            "No \(current.metric.title) Data",
                            systemImage: "chart.bar.xaxis",
                            description: Text("No teams have an available value for this metric.")
                        )
                    } else {
                        ScrollView {
                            OPRBarChart(
                                metric: current.metric,
                                entries: current.entries,
                                valueDomain: current.valueDomain,
                                teamDomain: current.teamDomain,
                                rowHeight: 21,
                                minimumHeight: 160,
                                desiredTickCount: 4
                            )
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                        }
                    }
                }
                .id(current.metric)
                .transition(.opacity)
            }
        }
    }
}

private struct OPRLeaderReadout: View {
    @Environment(\.colorScheme) private var colorScheme
    let series: OPRChartSeries

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HUDLabel("LEADER · \(series.metric.title)")
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    NumericValueView(value: series.leader?.value, fractionLength: 1 ... 1)
                        .font(.hudNumeric(size: 26, weight: .medium))
                    if let leader = series.leader {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(TeamChartColorIdentity.color(for: leader.teamNumber, in: colorScheme))
                                .frame(width: 6, height: 6)
                            Text(verbatim: "#\(leader.teamLabel)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                HUDLabel("FIELD AVG")
                    .foregroundStyle(.secondary)
                NumericValueView(value: series.averageValue, fractionLength: 1 ... 1)
                    .font(.hudNumeric(size: 14, weight: .medium))
                    .padding(.bottom, 3)
            }
        }
        .padding(12)
        .hudPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(series.metric.accessibilityTitle) leader")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let leader = series.leader else { return "Unavailable" }
        var value = "Team \(leader.teamLabel), \(leader.value.formatted(.number.precision(.fractionLength(1))))"
        if let average = series.averageValue {
            value += ". Field average \(average.formatted(.number.precision(.fractionLength(1))))"
        }
        return value
    }
}

struct OPRFullChartSheet: View {
    @Environment(\.dismiss) private var dismiss
    let series: OPRChartSeries

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(series.metric.title) — All Teams")
                        .font(.title2.weight(.semibold))
                    Text("\(series.availableTeamCount) teams with available values · colors match every OPR chart")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            if series.entries.isEmpty {
                ContentUnavailableView(
                    "No \(series.metric.title) Data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("No teams have an available value for this metric.")
                )
            } else {
                ScrollView {
                    OPRBarChart(
                        metric: series.metric,
                        entries: series.entries,
                        valueDomain: series.valueDomain,
                        teamDomain: series.teamDomain,
                        rowHeight: 28,
                        minimumHeight: 420,
                        desiredTickCount: 6
                    )
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }
}

extension TeamChartColorIdentity {
    static func color(for teamNumber: Int, in colorScheme: ColorScheme) -> Color {
        Color(
            hue: hue(for: teamNumber),
            saturation: colorScheme == .dark ? 0.68 : 0.78,
            brightness: colorScheme == .dark ? 0.90 : 0.58
        )
    }
}

private struct OPRBarChart: View {
    @Environment(\.colorScheme) private var colorScheme
    let metric: OPRChartMetric
    let entries: [OPRChartEntry]
    let valueDomain: ClosedRange<Double>
    let teamDomain: [String]
    let rowHeight: CGFloat
    let minimumHeight: CGFloat
    let desiredTickCount: Int

    var body: some View {
        Chart {
            ForEach(entries) { entry in
                BarMark(
                    xStart: .value("Zero baseline", 0),
                    xEnd: .value(metric.accessibilityTitle, entry.value),
                    y: .value("Team", entry.teamLabel),
                    height: .ratio(0.58)
                )
                .foregroundStyle(barGradient(for: entry))
                .clipShape(Capsule())
                .annotation(
                    position: entry.value >= 0 ? .trailing : .leading,
                    spacing: 5
                ) {
                    Text(entry.value, format: .number.precision(.fractionLength(1)))
                        .font(.hudNumeric(size: 10.5, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Team \(entry.teamLabel)")
                .accessibilityValue(
                    entry.value.formatted(.number.precision(.fractionLength(2)))
                )
            }

            RuleMark(x: .value("Zero", 0))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Color.primary.opacity(0.28))
        }
        .chartXScale(domain: valueDomain)
        .chartYScale(domain: teamDomain)
        .chartXAxis {
            AxisMarks(position: .bottom, values: .automatic(desiredCount: desiredTickCount)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.primary.opacity(0.18))
                // Explicit colors: hierarchical styles inside Charts derive from the accent tint.
                AxisValueLabel()
                    .font(.hudNumeric(size: 9))
                    .foregroundStyle(Color.primary.opacity(0.45))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisValueLabel()
                    .font(.hudNumeric(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
        }
        .chartLegend(.hidden)
        .frame(height: max(minimumHeight, CGFloat(entries.count) * rowHeight + 24))
        .accessibilityLabel("\(metric.accessibilityTitle) team rankings")
        .accessibilityHint("Horizontal bars compare teams; each bar is also labeled by team number and value.")
    }

    /// Bars brighten toward their value end, so the eye lands on the labeled tip.
    private func barGradient(for entry: OPRChartEntry) -> LinearGradient {
        let color = TeamChartColorIdentity.color(for: entry.teamNumber, in: colorScheme)
        let isPositive = entry.value >= 0
        return LinearGradient(
            colors: [color.opacity(0.45), color],
            startPoint: isPositive ? .leading : .trailing,
            endPoint: isPositive ? .trailing : .leading
        )
    }
}

private struct RankingsControls: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            HUDLabel("SORT")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Picker("Sort by", selection: $model.sortField) {
                ForEach(model.availableSortFields) { field in
                    SortFieldLabel(field: field)
                        .tag(field)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Button {
                model.sortDirection = isAscending ? .descending : .ascending
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isAscending ? 180 : 0))
                    HUDLabel(isAscending ? "ASC" : "DESC")
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(HUDCardButtonStyle(cornerRadius: 6))
            .animation(reduceMotion ? nil : .hudEaseInOut, value: isAscending)
            .help(isAscending ? "Sorted ascending — click to sort descending" : "Sorted descending — click to sort ascending")
            .accessibilityLabel("Sort direction")
            .accessibilityValue(isAscending ? "Ascending" : "Descending")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var isAscending: Bool {
        model.sortDirection == .ascending
    }
}

private struct SortFieldLabel: View {
    let field: RankingSortField

    var body: some View {
        switch field {
        case .storedRank: Text("Event rank")
        case .teamNumber: Text("Team number")
        case .totalOPR: Text("OPR")
        case .oprc: Text("OPRc")
        case .nonPenaltyOPR: Text("Non-penalty OPR")
        case .autoOPR: Text("Auto OPR")
        case .teleopOPR: Text("Teleop OPR")
        case .endgameOPR: Text("Endgame OPR")
        case .teamName: Text("Team name")
        case .highestOPR: Text("Highest OPR")
        case .bestSeason: Text("Best season")
        case .rookieYear: Text("Rookie year")
        }
    }
}

private struct LiveRankingsTable: View {
    @Bindable var model: AppModel
    let rows: [RankedStanding]
    let eventCode: String
    let teamMetrics: [Int: TeamOPRcMetric]
    let present: (RankingPresentation) -> Void

    var body: some View {
        let scale = SortedColumnScale(
            field: model.sortField,
            values: rows.map { metricValue(model.sortField, for: $0) }
        )

        Table(rows, sortOrder: model.rankingTableSortOrder) {
            TableColumn("#") { row in
                RankingOrderText(order: row.order, total: rows.count)
            }
            .width(min: 36, ideal: 44, max: 60)
            .alignment(.numeric)

            TableColumn("Rank", sortUsing: RankingColumnComparator(.storedRank)) { row in
                Text(row.team.storedRank.formatted())
                    .font(.hudNumeric(weight: scale.isSorted(.storedRank) ? .semibold : .regular))
            }
            .width(min: 52, ideal: 60, max: 74)
            .alignment(.numeric)

            TableColumn("Team", sortUsing: RankingColumnComparator(.teamNumber)) { row in
                Button {
                    present(.matches(eventCode: eventCode, teamNumber: row.team.teamNumber))
                } label: {
                    Text(row.team.teamNumber.teamNumberText)
                        .font(.hudNumeric(weight: scale.isSorted(.teamNumber) ? .semibold : .medium))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Show match history for Team \(row.team.teamNumber.teamNumberText)")
                .accessibilityLabel("Team \(row.team.teamNumber.teamNumberText), show match history")
            }
            .width(min: 72, ideal: 84, max: 100)

            TableColumn("Tags") { row in
                TeamTagsTableCell(
                    tags: model.tags(eventCode: eventCode, teamNumber: row.team.teamNumber)
                ) {
                    present(.tags(eventCode: eventCode, teamNumber: row.team.teamNumber))
                }
            }
            .width(min: 90, ideal: 130, max: 190)

            metricColumn("OPR", field: .totalOPR, scale: scale)

            TableColumn("OPRc", sortUsing: RankingColumnComparator(.oprc)) { row in
                RankingMetricCell(
                    value: metricValue(.oprc, for: row),
                    scale: scale,
                    field: .oprc
                )
                .help("Calculated OPR after one residual-IQR outlier filtering pass")
            }
            .width(min: 78, ideal: 92, max: 120)
            .alignment(.numeric)

            metricColumn("npOPR", field: .nonPenaltyOPR, scale: scale)
            metricColumn("Auto", field: .autoOPR, scale: scale)
            metricColumn("Teleop", field: .teleopOPR, scale: scale)
            metricColumn("Endgame", field: .endgameOPR, scale: scale)
        }
        .tableStyle(.inset)
    }

    private func metricColumn(
        _ title: LocalizedStringKey,
        field: RankingSortField,
        scale: SortedColumnScale
    ) -> some TableColumnContent<RankedStanding, RankingColumnComparator> {
        TableColumn(title, sortUsing: RankingColumnComparator(field)) { row in
            RankingMetricCell(
                value: metricValue(field, for: row),
                scale: scale,
                field: field
            )
        }
        .width(min: 78, ideal: 92, max: 120)
        .alignment(.numeric)
    }

    private func metricValue(_ field: RankingSortField, for row: RankedStanding) -> Double? {
        switch field {
        case .totalOPR: row.team.totalOPR
        case .oprc: teamMetrics[row.team.teamNumber]?.oprc
        case .nonPenaltyOPR: row.team.nonPenaltyOPR
        case .autoOPR: row.team.autoOPR
        case .teleopOPR: row.team.teleopOPR
        case .endgameOPR: row.team.endgameOPR
        default: nil
        }
    }
}

private struct PreviewRankingsTable: View {
    @Bindable var model: AppModel
    let rows: [RankedStanding]
    let eventCode: String
    let season: Int
    let present: (RankingPresentation) -> Void

    var body: some View {
        let scale = SortedColumnScale(
            field: model.sortField,
            values: model.sortField == .highestOPR ? rows.map(\.team.highestOPR) : []
        )

        Table(rows, sortOrder: model.rankingTableSortOrder) {
            TableColumn("Rank") { row in
                RankingOrderText(order: row.order, total: rows.count)
            }
            .width(min: 48, ideal: 56, max: 70)
            .alignment(.numeric)

            TableColumn("Team", sortUsing: RankingColumnComparator(.teamNumber)) { row in
                Text(row.team.teamNumber.teamNumberText)
                    .font(.hudNumeric(weight: scale.isSorted(.teamNumber) ? .semibold : .medium))
            }
            .width(min: 72, ideal: 84, max: 100)

            TableColumn("Team Name", sortUsing: RankingColumnComparator(.teamName)) { row in
                Text(row.team.teamName.isEmpty ? "—" : row.team.teamName)
                    .fontWeight(scale.isSorted(.teamName) ? .semibold : .regular)
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 210, max: 400)

            TableColumn("Tags") { row in
                TeamTagsTableCell(
                    tags: model.tags(eventCode: eventCode, teamNumber: row.team.teamNumber)
                ) {
                    present(.tags(eventCode: eventCode, teamNumber: row.team.teamNumber))
                }
            }
            .width(min: 90, ideal: 130, max: 190)

            TableColumn("Highest OPR", sortUsing: RankingColumnComparator(.highestOPR)) { row in
                RankingMetricCell(value: row.team.highestOPR, scale: scale, field: .highestOPR)
            }
            .width(min: 100, ideal: 116, max: 140)
            .alignment(.numeric)

            TableColumn("Best Season", sortUsing: RankingColumnComparator(.bestSeason)) { row in
                OptionalIntegerValue(value: row.team.bestSeason, usesGrouping: false)
                    .font(.hudNumeric(weight: scale.isSorted(.bestSeason) ? .semibold : .regular))
            }
            .width(min: 92, ideal: 104, max: 120)
            .alignment(.numeric)

            TableColumn("\(String(season))") { row in
                NumericValueView(value: row.team.perSeason[String(season)]?.total, fractionDigits: 2)
                    .font(.hudNumeric())
            }
            .width(min: 66, ideal: 78, max: 96)
            .alignment(.numeric)

            TableColumn("\(String(season - 1))") { row in
                NumericValueView(value: row.team.perSeason[String(season - 1)]?.total, fractionDigits: 2)
                    .font(.hudNumeric())
            }
            .width(min: 66, ideal: 78, max: 96)
            .alignment(.numeric)

            TableColumn("\(String(season - 2))") { row in
                NumericValueView(value: row.team.perSeason[String(season - 2)]?.total, fractionDigits: 2)
                    .font(.hudNumeric())
            }
            .width(min: 66, ideal: 78, max: 96)
            .alignment(.numeric)

            TableColumn("Rookie Year", sortUsing: RankingColumnComparator(.rookieYear)) { row in
                OptionalIntegerValue(value: row.team.rookieYear, usesGrouping: false)
                    .font(.hudNumeric(weight: scale.isSorted(.rookieYear) ? .semibold : .regular))
            }
            .width(min: 92, ideal: 104, max: 120)
            .alignment(.numeric)
        }
        .tableStyle(.inset)
    }
}

/// Identifies a sortable ranking column. Rows arrive already sorted by `AppModel`,
/// so the comparator only preserves that order; Table uses it for header state.
struct RankingColumnComparator: SortComparator, Hashable {
    let field: RankingSortField
    var order: SortOrder

    init(_ field: RankingSortField, order: SortOrder? = nil) {
        self.field = field
        self.order = order ?? field.defaultTableSortOrder
    }

    func compare(_ lhs: RankedStanding, _ rhs: RankedStanding) -> ComparisonResult {
        if lhs.order == rhs.order { return .orderedSame }
        return lhs.order < rhs.order ? .orderedAscending : .orderedDescending
    }
}

extension RankingSortField {
    /// The direction a column sorts in when its header is first clicked:
    /// identifiers ascend, performance metrics put the strongest teams first.
    var defaultTableSortOrder: SortOrder {
        switch self {
        case .storedRank, .teamNumber, .teamName, .rookieYear: .forward
        case .totalOPR, .oprc, .nonPenaltyOPR, .autoOPR, .teleopOPR, .endgameOPR,
             .highestOPR, .bestSeason: .reverse
        }
    }
}

extension AppModel {
    var rankingTableSortOrder: Binding<[RankingColumnComparator]> {
        Binding {
            [RankingColumnComparator(
                self.sortField,
                order: self.sortDirection == .ascending ? .forward : .reverse
            )]
        } set: { newValue in
            guard let comparator = newValue.first else { return }
            let direction: SortDirection = comparator.order == .forward ? .ascending : .descending
            if self.sortField != comparator.field {
                self.sortField = comparator.field
            }
            if self.sortDirection != direction {
                self.sortDirection = direction
            }
        }
    }
}

/// Scales the actively sorted metric so its cells can show an in-cell magnitude bar.
struct SortedColumnScale {
    let field: RankingSortField
    private let maximum: Double

    init(field: RankingSortField, values: [Double?]) {
        self.field = field
        maximum = values.compactMap { $0 }.filter(\.isFinite).max() ?? 0
    }

    func isSorted(_ candidate: RankingSortField) -> Bool {
        candidate == field
    }

    /// The bar length from 0 to 1. Negative and unavailable values have no bar.
    func fraction(for value: Double?, in candidate: RankingSortField) -> Double {
        guard candidate == field,
              let value,
              value.isFinite,
              value > 0,
              maximum > 0 else {
            return 0
        }
        return min(value / maximum, 1)
    }
}

private struct RankingMetricCell: View {
    let value: Double?
    let scale: SortedColumnScale
    let field: RankingSortField

    var body: some View {
        let isSorted = scale.isSorted(field)

        NumericValueView(value: value, fractionDigits: 2)
            .font(.hudNumeric(weight: isSorted ? .semibold : .regular))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.bottom, isSorted ? 5 : 0)
            .overlay(alignment: .bottom) {
                if isSorted {
                    HUDGauge(fraction: scale.fraction(for: value, in: field))
                }
            }
    }
}

/// The display order, zero-padded to the field size so every row has the same width.
private struct RankingOrderText: View {
    let order: Int
    let total: Int

    var body: some View {
        let width = max(String(total).count, 2)
        Text(verbatim: String(repeating: "0", count: max(width - String(order).count, 0)) + String(order))
            .font(.hudNumeric(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .accessibilityLabel(order.formatted())
    }
}

private struct OptionalIntegerValue: View {
    let value: Int?
    var usesGrouping = true

    var body: some View {
        if let value {
            Text(usesGrouping ? value.formatted() : String(value))
                .monospacedDigit()
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Unavailable")
        }
    }
}

private struct TeamTagsTableCell: View {
    let tags: [TeamTag]
    let edit: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 5) {
                TeamTagsSummaryView(tags: tags)
                Spacer(minLength: 4)
                Image(systemName: "plus.circle")
                    .foregroundStyle(isHovering ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { isHovering = $0 }
        .help(tags.isEmpty ? "Add a team tag" : "Edit team tags")
        .accessibilityLabel(tags.isEmpty ? "Add team tag" : "Edit team tags")
    }
}

enum RankingPresentation: Identifiable, Equatable {
    case matches(TeamSelection)
    case tags(TeamSelection)
    case chart(OPRChartSeries)

    var id: String {
        switch self {
        case .matches(let selection):
            return "matches:\(selection.id)"
        case .tags(let selection):
            return "tags:\(selection.id)"
        case .chart(let series):
            return "chart:\(series.metric.rawValue)"
        }
    }

    static func matches(eventCode: String, teamNumber: Int) -> RankingPresentation {
        .matches(
            TeamSelection(eventCode: eventCode, teamNumber: teamNumber)
        )
    }

    static func tags(eventCode: String, teamNumber: Int) -> RankingPresentation {
        .tags(
            TeamSelection(eventCode: eventCode, teamNumber: teamNumber)
        )
    }
}
