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
    let showFullChart: (OPRChartSeries) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Compare OPR Leaders")
                    .font(.headline)
                Text("Top 10 per metric · independent scales · click to expand")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                ScrollView {
                    LazyVStack(spacing: 12) {
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
        .background(.background)
    }
}

private struct OPRMetricChartButton: View {
    let series: OPRChartSeries
    let showFullChart: () -> Void

    var body: some View {
        Button(action: showFullChart) {
            GroupBox {
                if series.summaryEntries.isEmpty {
                    Text("No values available")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    OPRBarChart(
                        metric: series.metric,
                        entries: series.summaryEntries,
                        valueDomain: series.summaryValueDomain,
                        teamDomain: series.summaryTeamDomain,
                        rowHeight: 23,
                        minimumHeight: 112,
                        desiredTickCount: 3
                    )
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(series.metric.title)
                        .font(.headline)
                    Spacer()
                    Text(teamCountLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(series.summaryEntries.isEmpty)
        .help("Show all teams for \(series.metric.title)")
        .accessibilityLabel("\(series.metric.accessibilityTitle) chart")
        .accessibilityValue(teamCountLabel)
        .accessibilityHint("Open a larger chart containing every team with an available value.")
    }

    private var teamCountLabel: String {
        if series.availableTeamCount > series.summaryEntries.count {
            return "Top \(series.summaryEntries.count) of \(series.availableTeamCount)"
        }
        return "\(series.summaryEntries.count) teams"
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
                    y: .value("Team", entry.teamLabel)
                )
                .foregroundStyle(teamColor(for: entry.teamNumber))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .annotation(
                    position: entry.value >= 0 ? .trailing : .leading,
                    spacing: 5
                ) {
                    Text(entry.value, format: .number.precision(.fractionLength(1)))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Team \(entry.teamLabel)")
                .accessibilityValue(
                    entry.value.formatted(.number.precision(.fractionLength(2)))
                )
            }

            RuleMark(x: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.65))
        }
        .chartXScale(domain: valueDomain)
        .chartYScale(domain: teamDomain)
        .chartXAxis {
            AxisMarks(position: .bottom, values: .automatic(desiredCount: desiredTickCount)) {
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisValueLabel()
                    .font(.caption.monospacedDigit())
            }
        }
        .chartLegend(.hidden)
        .frame(height: max(minimumHeight, CGFloat(entries.count) * rowHeight + 24))
        .accessibilityLabel("\(metric.accessibilityTitle) team rankings")
        .accessibilityHint("Horizontal bars compare teams; each bar is also labeled by team number and value.")
    }

    private func teamColor(for teamNumber: Int) -> Color {
        Color(
            hue: TeamChartColorIdentity.hue(for: teamNumber),
            saturation: colorScheme == .dark ? 0.68 : 0.78,
            brightness: colorScheme == .dark ? 0.90 : 0.58
        )
    }
}

private struct RankingsControls: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Picker("Sort by", selection: $model.sortField) {
                ForEach(model.availableSortFields) { field in
                    SortFieldLabel(field: field)
                        .tag(field)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220)

            Button {
                model.sortDirection = model.sortDirection == .ascending
                    ? .descending
                    : .ascending
            } label: {
                Label(
                    model.sortDirection == .ascending ? "Ascending" : "Descending",
                    systemImage: model.sortDirection == .ascending
                        ? "arrow.up"
                        : "arrow.down"
                )
            }
            .help(model.sortDirection == .ascending ? "Sort ascending" : "Sort descending")

            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.rankedStandings.count, format: .number)
                    .font(.title3.monospacedDigit())
                Text("teams")
                    .font(.callout)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                Text(row.order.formatted())
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 36, ideal: 44, max: 60)
            .alignment(.numeric)

            TableColumn("Rank", sortUsing: RankingColumnComparator(.storedRank)) { row in
                Text(row.team.storedRank.formatted())
                    .font(.title3)
                    .monospacedDigit()
                    .fontWeight(scale.isSorted(.storedRank) ? .semibold : .regular)
            }
            .width(min: 52, ideal: 60, max: 74)
            .alignment(.numeric)

            TableColumn("Team", sortUsing: RankingColumnComparator(.teamNumber)) { row in
                Button {
                    present(.matches(eventCode: eventCode, teamNumber: row.team.teamNumber))
                } label: {
                    Text(row.team.teamNumber.teamNumberText)
                        .font(.title3.monospacedDigit())
                        .fontWeight(scale.isSorted(.teamNumber) ? .semibold : .regular)
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
                Text(row.order.formatted())
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 48, ideal: 56, max: 70)
            .alignment(.numeric)

            TableColumn("Team", sortUsing: RankingColumnComparator(.teamNumber)) { row in
                Text(row.team.teamNumber.teamNumberText)
                    .font(.title3)
                    .monospacedDigit()
                    .fontWeight(scale.isSorted(.teamNumber) ? .semibold : .regular)
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
                    .font(.title3.monospacedDigit())
                    .fontWeight(scale.isSorted(.bestSeason) ? .semibold : .regular)
            }
            .width(min: 92, ideal: 104, max: 120)
            .alignment(.numeric)

            TableColumn("\(String(season))") { row in
                NumericValueView(value: row.team.perSeason[String(season)]?.total, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 66, ideal: 78, max: 96)
            .alignment(.numeric)

            TableColumn("\(String(season - 1))") { row in
                NumericValueView(value: row.team.perSeason[String(season - 1)]?.total, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 66, ideal: 78, max: 96)
            .alignment(.numeric)

            TableColumn("\(String(season - 2))") { row in
                NumericValueView(value: row.team.perSeason[String(season - 2)]?.total, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 66, ideal: 78, max: 96)
            .alignment(.numeric)

            TableColumn("Rookie Year", sortUsing: RankingColumnComparator(.rookieYear)) { row in
                OptionalIntegerValue(value: row.team.rookieYear, usesGrouping: false)
                    .font(.title3.monospacedDigit())
                    .fontWeight(scale.isSorted(.rookieYear) ? .semibold : .regular)
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
        let fraction = scale.fraction(for: value, in: field)

        NumericValueView(value: value, fractionDigits: 2)
            .font(.title3.monospacedDigit())
            .fontWeight(isSorted ? .semibold : .regular)
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(alignment: .leading) {
                if fraction > 0 {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(0.22))
                            .frame(width: proxy.size.width * fraction)
                    }
                    .accessibilityHidden(true)
                }
            }
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
