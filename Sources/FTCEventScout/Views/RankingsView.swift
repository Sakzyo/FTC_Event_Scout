import Charts
import SwiftUI

/// The Rankings tab in ftcscout.org's style: a tabbed stats card beside an OPR leaders card,
/// both resting on a soft gray page.
struct RankingsView: View {
    @Bindable var model: AppModel
    let event: EventData
    let present: (RankingPresentation) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ScoutTabbedCard(title: "Rankings", systemImage: "list.number") {
                Text(verbatim: "\(event.standings.count) teams")
            } content: {
                VStack(alignment: .leading, spacing: 10) {
                    RankingsControls(model: model)
                    RankingsStatTable(model: model, event: event, present: present)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            ScoutTabbedCard(
                title: "OPR Leaders",
                systemImage: "chart.bar.xaxis",
                contentPadding: 0
            ) {
                if event.mode == .live {
                    Text(model.oprChartLayout == .stacked ? "Top 10 · click to expand" : "All teams")
                }
            } content: {
                OPRChartsPanel(
                    mode: event.mode,
                    series: event.oprChartSeries,
                    layout: model.oprChartLayout,
                    showFullChart: { present(.chart($0)) }
                )
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 380, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Compare OPR Leaders")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

private struct RankingsControls: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHoveringMenu = false

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Sort by", selection: $model.sortField) {
                    ForEach(model.availableSortFields) { field in
                        Text(field.menuTitle).tag(field)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text("Sort: \(model.sortField.menuTitle)")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.system(size: 12, weight: .medium))
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(
                isHoveringMenu ? AnyShapeStyle(.scoutFormHover) : AnyShapeStyle(.scoutFormBackground),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(.scoutSeparator, lineWidth: 1))
            .onHover { isHoveringMenu = $0 }
            .animation(.scoutHover, value: isHoveringMenu)
            .accessibilityLabel("Sort by")
            .accessibilityValue(model.sortField.menuTitle)

            Button {
                model.sortDirection = isAscending ? .descending : .ascending
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isAscending ? 180 : 0))
                        .animation(reduceMotion ? nil : .scoutMove, value: isAscending)
                    Text(isAscending ? "Ascending" : "Descending")
                }
            }
            .buttonStyle(ScoutPillButtonStyle())
            .help(isAscending ? "Sorted ascending — click to sort descending" : "Sorted descending — click to sort ascending")
            .accessibilityLabel("Sort direction")
            .accessibilityValue(isAscending ? "Ascending" : "Descending")

            Spacer(minLength: 8)

            Text("Click a header to sort, a row for match history")
                .font(.system(size: 11))
                .foregroundStyle(.scoutSecondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityHidden(true)
        }
    }

    private var isAscending: Bool {
        model.sortDirection == .ascending
    }
}

extension RankingSortField {
    /// The name shown in the sort menu.
    var menuTitle: String {
        switch self {
        case .storedRank: "Event rank"
        case .teamNumber: "Team number"
        case .record: "Record"
        case .played: "Matches played"
        case .totalOPR: "OPR"
        case .oprc: "OPRc"
        case .nonPenaltyOPR: "Non-penalty OPR"
        case .autoOPR: "Auto OPR"
        case .teleopOPR: "Teleop OPR"
        case .endgameOPR: "Endgame OPR"
        case .teamName: "Team name"
        case .highestOPR: "Highest OPR"
        case .bestSeason: "Best season"
        case .rookieYear: "Rookie year"
        }
    }
}

// MARK: - OPR leaders

private struct OPRChartsPanel: View {
    let mode: EventMode
    let series: [OPRChartSeries]
    let layout: OPRChartLayout
    let showFullChart: (OPRChartSeries) -> Void

    var body: some View {
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

struct OPRMetricChartButton: View {
    let series: OPRChartSeries
    let showFullChart: () -> Void

    var body: some View {
        Button(action: showFullChart) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: series.metric.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(verbatim: teamCountLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.scoutSecondaryText)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.scoutTheme)
                        .accessibilityHidden(true)
                }

                if series.summaryEntries.isEmpty {
                    Text("No values available")
                        .font(.caption)
                        .foregroundStyle(.scoutSecondaryText)
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
        }
        .buttonStyle(ScoutCardButtonStyle())
        .disabled(series.summaryEntries.isEmpty)
        .help("Show all teams for \(series.metric.title)")
        .accessibilityLabel("\(series.metric.accessibilityTitle) chart")
        .accessibilityValue(accessibilityCountLabel)
        .accessibilityHint("Open a larger chart containing every team with an available value.")
    }

    private var teamCountLabel: String {
        if series.availableTeamCount > series.summaryEntries.count {
            return "Top \(series.summaryEntries.count) of \(series.availableTeamCount)"
        }
        return "\(series.summaryEntries.count) teams"
    }

    private var accessibilityCountLabel: String {
        teamCountLabel
    }
}

/// One metric at a time: pill switcher, a leader readout, and every team's bar.
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
        VStack(alignment: .leading, spacing: 0) {
            ScoutPillPicker(
                accessibilityTitle: "OPR metric",
                options: series.map(\.metric),
                selection: selection,
                title: \.shortTitle
            )
            .padding([.horizontal, .top], 12)

            if let current = selectedSeries {
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
        }
    }
}

struct OPRLeaderReadout: View {
    @Environment(\.colorScheme) private var colorScheme
    let series: OPRChartSeries

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "Leader · \(series.metric.title)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.scoutSecondaryText)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    NumericValueView(value: series.leader?.value, fractionLength: 1 ... 1)
                        .font(.scoutNumeric(size: 24, weight: .bold))
                    if let leader = series.leader {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(TeamChartColorIdentity.color(for: leader.teamNumber, in: colorScheme))
                                .frame(width: 7, height: 7)
                            Text(verbatim: "Team \(leader.teamLabel)")
                                .font(.scoutNumeric(size: 12, weight: .semibold))
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("Field avg")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.scoutSecondaryText)
                NumericValueView(value: series.averageValue, fractionLength: 1 ... 1)
                    .font(.scoutNumeric(size: 15, weight: .semibold))
                    .padding(.bottom, 3)
            }
        }
        .padding(12)
        .background(.scoutCard, in: shape)
        .overlay(shape.strokeBorder(.scoutSeparator, lineWidth: 1))
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
                    height: .ratio(0.62)
                )
                .foregroundStyle(TeamChartColorIdentity.color(for: entry.teamNumber, in: colorScheme))
                .cornerRadius(2)
                .annotation(
                    position: entry.value >= 0 ? .trailing : .leading,
                    spacing: 5
                ) {
                    Text(entry.value, format: .number.precision(.fractionLength(1)))
                        .font(.scoutNumeric(size: 10.5, weight: .medium))
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
            AxisMarks(position: .bottom, values: .automatic(desiredCount: desiredTickCount)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.12))
                // Explicit colors: hierarchical styles inside Charts derive from the accent tint.
                // fixedSize keeps the tick on the plot's trailing edge from truncating to "…".
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(number, format: .number.precision(.fractionLength(0...1)))
                            .font(.scoutNumeric(size: 9))
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisValueLabel()
                    .font(.scoutNumeric(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
        }
        .chartLegend(.hidden)
        .frame(height: max(minimumHeight, CGFloat(entries.count) * rowHeight + 24))
        .accessibilityLabel("\(metric.accessibilityTitle) team rankings")
        .accessibilityHint("Horizontal bars compare teams; each bar is also labeled by team number and value.")
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
