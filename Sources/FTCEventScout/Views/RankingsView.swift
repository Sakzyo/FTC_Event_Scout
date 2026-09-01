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
                Text("Top 10 teams per metric · each chart uses its own scale")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(
                    "Click a chart to view every team",
                    systemImage: "arrow.up.left.and.arrow.down.right"
                )
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
                .annotation(
                    position: entry.value >= 0 ? .trailing : .leading,
                    spacing: 4
                ) {
                    Text(entry.value, format: .number.precision(.fractionLength(1)))
                        .font(.caption2.monospacedDigit())
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
        Table(rows) {
            TableColumn("Order") { row in
                Text(row.order.formatted())
                    .font(.title3)
                    .monospacedDigit()
            }
            .width(min: 52, ideal: 58, max: 72)

            TableColumn("Rank") { row in
                Text(row.team.storedRank.formatted())
                    .font(.title3)
                    .monospacedDigit()
            }
            .width(min: 48, ideal: 56, max: 70)

            TableColumn("Team") { row in
                Button {
                    present(.matches(eventCode: eventCode, teamNumber: row.team.teamNumber))
                } label: {
                    Text(row.team.teamNumber.teamNumberText)
                        .font(.title3.monospacedDigit())
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

            TableColumn("OPR") { row in
                NumericValueView(value: row.team.totalOPR, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 70, ideal: 86, max: 110)

            TableColumn("OPRc") { row in
                NumericValueView(
                    value: teamMetrics[row.team.teamNumber]?.oprc,
                    fractionDigits: 2
                )
                .font(.title3.monospacedDigit())
                .help("Calculated OPR after one residual-IQR outlier filtering pass")
            }
            .width(min: 70, ideal: 86, max: 110)

            TableColumn("npOPR") { row in
                NumericValueView(value: row.team.nonPenaltyOPR, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 70, ideal: 86, max: 110)

            TableColumn("Auto") { row in
                NumericValueView(value: row.team.autoOPR, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 70, ideal: 86, max: 110)

            TableColumn("Teleop") { row in
                NumericValueView(value: row.team.teleopOPR, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 70, ideal: 86, max: 110)

            TableColumn("Endgame") { row in
                NumericValueView(value: row.team.endgameOPR, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 70, ideal: 86, max: 110)
        }
        .tableStyle(.inset)
    }
}

private struct PreviewRankingsTable: View {
    @Bindable var model: AppModel
    let rows: [RankedStanding]
    let eventCode: String
    let season: Int
    let present: (RankingPresentation) -> Void

    var body: some View {
        Table(rows) {
            TableColumn("Rank") { row in
                Text(row.order.formatted())
                    .font(.title3)
                    .monospacedDigit()
            }
            .width(min: 48, ideal: 56, max: 70)

            TableColumn("Team") { row in
                Text(row.team.teamNumber.teamNumberText)
                    .font(.title3)
                    .monospacedDigit()
            }
            .width(min: 72, ideal: 84, max: 100)

            TableColumn("Team Name") { row in
                Text(row.team.teamName.isEmpty ? "—" : row.team.teamName)
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

            TableColumn("Highest OPR") { row in
                NumericValueView(value: row.team.highestOPR, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 92, ideal: 110, max: 130)

            TableColumn("Best Season") { row in
                OptionalIntegerValue(value: row.team.bestSeason)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 82, ideal: 96, max: 110)

            TableColumn("\(season)") { row in
                NumericValueView(value: row.team.perSeason[String(season)]?.total, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 66, ideal: 78, max: 96)

            TableColumn("\(season - 1)") { row in
                NumericValueView(value: row.team.perSeason[String(season - 1)]?.total, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 66, ideal: 78, max: 96)

            TableColumn("\(season - 2)") { row in
                NumericValueView(value: row.team.perSeason[String(season - 2)]?.total, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 66, ideal: 78, max: 96)

            TableColumn("Rookie Year") { row in
                OptionalIntegerValue(value: row.team.rookieYear)
                    .font(.title3.monospacedDigit())
            }
            .width(min: 82, ideal: 96, max: 110)
        }
        .tableStyle(.inset)
    }
}

private struct OptionalIntegerValue: View {
    let value: Int?

    var body: some View {
        if let value {
            Text(value.formatted())
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

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 5) {
                TeamTagsSummaryView(tags: tags)
                Spacer(minLength: 4)
                Image(systemName: "plus.circle")
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
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
