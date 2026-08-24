import Charts
import SwiftUI

struct RankingsView: View {
    @Bindable var model: AppModel
    let event: EventData
    @State private var presentedSheet: RankingSheet?

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
                        presentedSheet: $presentedSheet
                    )
                case .preview:
                    PreviewRankingsTable(
                        model: model,
                        rows: model.rankedStandings,
                        eventCode: event.eventCode,
                        season: event.season,
                        presentedSheet: $presentedSheet
                    )
                }

                Divider()

                OPRChartsPanel(mode: event.mode, series: event.oprChartSeries)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet.kind {
            case .matches:
                TeamMatchHistoryView(model: model, selection: sheet.selection)
            case .tags:
                TagEditorView(model: model, selection: sheet.selection)
            }
        }
    }
}

private struct OPRChartsPanel: View {
    let mode: EventMode
    let series: [OPRChartSeries]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Compare OPR Leaders")
                    .font(.headline)
                Text("Top 10 teams per metric · each chart uses its own scale")
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
                            OPRMetricChart(series: metricSeries)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(.background)
    }
}

private struct OPRMetricChart: View {
    let series: OPRChartSeries

    var body: some View {
        GroupBox {
            if series.entries.isEmpty {
                Text("No values available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                Chart {
                    ForEach(series.entries) { entry in
                        BarMark(
                            xStart: .value("Zero baseline", 0),
                            xEnd: .value(series.metric.accessibilityTitle, entry.value),
                            y: .value("Team", entry.teamLabel)
                        )
                        .foregroundStyle(.tint)
                        .annotation(
                            position: entry.value >= 0 ? .trailing : .leading,
                            spacing: 4
                        ) {
                            Text(entry.value, format: .number.precision(.fractionLength(1)))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                    }

                    RuleMark(x: .value("Zero", 0))
                        .foregroundStyle(.secondary.opacity(0.65))
                }
                .chartXScale(domain: series.valueDomain)
                .chartYScale(domain: series.teamDomain)
                .chartXAxis {
                    AxisMarks(position: .bottom, values: .automatic(desiredCount: 3)) {
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
                .frame(height: max(112, CGFloat(series.entries.count) * 23 + 24))
                .accessibilityLabel("\(series.metric.accessibilityTitle) team rankings")
                .accessibilityHint("Horizontal bars compare the highest available team values.")
            }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(series.metric.title)
                    .font(.headline)
                Spacer()
                Text(teamCountLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var teamCountLabel: String {
        if series.availableTeamCount > series.entries.count {
            return "Top \(series.entries.count) of \(series.availableTeamCount)"
        }
        return "\(series.entries.count) teams"
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
    @Binding var presentedSheet: RankingSheet?

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
                Button(row.team.teamNumber.teamNumberText) {
                    presentedSheet = .matches(eventCode: eventCode, teamNumber: row.team.teamNumber)
                }
                .font(.title3.monospacedDigit())
                .buttonStyle(.link)
                .accessibilityLabel("Team \(row.team.teamNumber.teamNumberText), show match history")
            }
            .width(min: 72, ideal: 84, max: 100)

            TableColumn("Tags") { row in
                TeamTagsTableCell(
                    tags: model.tags(eventCode: eventCode, teamNumber: row.team.teamNumber)
                ) {
                    presentedSheet = .tags(eventCode: eventCode, teamNumber: row.team.teamNumber)
                }
            }
            .width(min: 90, ideal: 130, max: 190)

            TableColumn("OPR") { row in
                NumericValueView(value: row.team.totalOPR, fractionDigits: 2)
                    .font(.title3.monospacedDigit())
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
    @Binding var presentedSheet: RankingSheet?

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
                    presentedSheet = .tags(eventCode: eventCode, teamNumber: row.team.teamNumber)
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
        HStack(spacing: 5) {
            TeamTagsSummaryView(tags: tags)
            Button(action: edit) {
                Image(systemName: "plus.circle")
                    .accessibilityLabel(tags.isEmpty ? "Add team tag" : "Edit team tags")
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RankingSheet: Identifiable {
    enum Kind {
        case matches
        case tags
    }

    let kind: Kind
    let selection: TeamSelection

    var id: String { "\(kind)-\(selection.id)" }

    static func matches(eventCode: String, teamNumber: Int) -> RankingSheet {
        RankingSheet(
            kind: .matches,
            selection: TeamSelection(eventCode: eventCode, teamNumber: teamNumber)
        )
    }

    static func tags(eventCode: String, teamNumber: Int) -> RankingSheet {
        RankingSheet(
            kind: .tags,
            selection: TeamSelection(eventCode: eventCode, teamNumber: teamNumber)
        )
    }
}
