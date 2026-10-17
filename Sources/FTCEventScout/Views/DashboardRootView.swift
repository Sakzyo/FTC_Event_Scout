import SwiftUI

struct DashboardRootView: View {
    @Bindable var model: AppModel
    @SceneStorage("selectedDashboardSection") private var selectedSectionRaw = DashboardSection.rankings.rawValue
    @State private var rankingPresentation: RankingPresentation?

    private var selectedSection: DashboardSection {
        DashboardSection(rawValue: selectedSectionRaw) ?? .rankings
    }

    var body: some View {
        NavigationSplitView {
            DashboardSidebar(model: model, selection: $selectedSectionRaw)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            DashboardDetail(
                model: model,
                selection: selectedSection,
                presentRankingContent: { rankingPresentation = $0 }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $rankingPresentation) { presentation in
            switch presentation {
            case .matches(let selection):
                TeamMatchHistoryView(model: model, selection: selection)
            case .tags(let selection):
                TagEditorView(model: model, selection: selection)
            case .chart(let series):
                OPRFullChartSheet(series: series)
            }
        }
    }
}

private struct DashboardSidebar: View {
    @Bindable var model: AppModel
    @Binding var selection: String

    var body: some View {
        List(selection: $selection) {
            Section("Event") {
                ForEach(DashboardSection.allCases) { section in
                    DashboardSidebarLabel(section: section)
                        .tag(section.rawValue)
                }
            }

            if let event = model.currentEvent {
                Section("Loaded Data") {
                    LabeledContent("Teams", value: event.standings.count.formatted())
                    LabeledContent("Matches", value: event.matches.count.formatted())
                }
            }
        }
        .navigationTitle("FTC Event Scout")
        .safeAreaInset(edge: .bottom) {
            if let event = model.currentEvent {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.eventCode)
                        .font(.headline.monospaced())
                    Text("\(FTCSeason.option(for: event.season).yearRange) · \(event.mode == .preview ? "Historical preview" : "Live event data")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.bar)
            }
        }
    }
}

private struct DashboardSidebarLabel: View {
    let section: DashboardSection

    var body: some View {
        switch section {
        case .rankings:
            Label("Rankings", systemImage: "list.number")
        case .predictions:
            Label("Predictions", systemImage: "sparkles.rectangle.stack")
        case .highlights:
            Label("Highlights", systemImage: "trophy")
        }
    }
}

private struct DashboardDetail: View {
    @Bindable var model: AppModel
    let selection: DashboardSection
    let presentRankingContent: (RankingPresentation) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let event = model.currentEvent {
                EventHeaderView(event: event, loadState: model.eventLoadState)
                    .padding(12)
                switch selection {
                case .rankings:
                    RankingsView(
                        model: model,
                        event: event,
                        present: presentRankingContent
                    )
                case .predictions:
                    Divider()
                    MatchPredictionsView(event: event)
                        .background(.background)
                case .highlights:
                    Divider()
                    HighlightsView(model: model, event: event)
                        .background(.background)
                }
            } else {
                EmptyDashboardView(loadState: model.eventLoadState, retry: model.refreshEvent)
            }
        }
        .background(model.currentEvent == nil ? AnyShapeStyle(.background) : AnyShapeStyle(.scoutPage))
        .navigationTitle(model.currentEvent?.eventCode ?? "Event")
    }
}

/// The event's title card, modeled on ftcscout.org: a bold season-and-name title,
/// then icon rows for the season, event code, data source, and headline figures.
struct EventHeaderView: View {
    let event: EventData
    let loadState: EventLoadState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: "\(event.season) \(event.eventName.isEmpty ? event.eventCode : event.eventName)")
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 12)

                if case .loading(let code) = loadState {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing \(code)")
                            .font(.system(size: 11))
                            .foregroundStyle(.scoutSecondaryText)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Refreshing \(code)")
                }
            }

            ScoutFlowLayout(spacing: 18, lineSpacing: 6) {
                ScoutInfoRow(systemImage: "calendar") {
                    Text(verbatim: "\(season.yearRange) · \(season.gameName)")
                }
                if !event.eventName.isEmpty {
                    ScoutInfoRow(systemImage: "number") {
                        Text(verbatim: event.eventCode)
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Event code \(event.eventCode)")
                }
                ScoutInfoRow(systemImage: event.mode == .live ? "dot.radiowaves.left.and.right" : "clock.arrow.circlepath") {
                    Text(event.mode == .live ? "Live event data" : "Historical preview")
                }
            }
            .font(.system(size: 12))

            Rectangle()
                .fill(.scoutSeparator)
                .frame(height: 1)
                .accessibilityHidden(true)

            ScoutFlowLayout(spacing: 22, lineSpacing: 8) {
                ForEach(event.overviewStats) { stat in
                    EventStatRow(stat: stat)
                }
            }

            if event.mode == .preview {
                ScoutInfoRow(systemImage: "info.circle") {
                    Text(event.statusMessage)
                        .foregroundStyle(.scoutSecondaryText)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                .font(.system(size: 11))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scoutCard()
    }

    private var season: FTCSeason {
        FTCSeason.option(for: event.season)
    }
}

private struct EventStatRow: View {
    let stat: EventOverviewStat

    var body: some View {
        ScoutInfoRow(systemImage: stat.symbolName) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(verbatim: stat.label)
                    .font(.system(size: 12))
                    .foregroundStyle(.scoutSecondaryText)
                NumericValueView(value: stat.value, fractionLength: stat.fractionLength)
                    .font(.scoutNumeric(size: 15, weight: .semibold))
                    .contentTransition(.numericText())
                if let detail = stat.detail {
                    Text(verbatim: detail)
                        .font(.scoutNumeric(size: 11))
                        .foregroundStyle(.scoutSecondaryText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let value = stat.value?.formatted(.number.precision(.fractionLength(stat.fractionLength)))
            ?? "Unavailable"
        guard let detail = stat.accessibilityDetail else { return value }
        return "\(value), \(detail)"
    }
}

private struct EmptyDashboardView: View {
    let loadState: EventLoadState
    let retry: () -> Void

    var body: some View {
        switch loadState {
        case .loading(let code):
            ContentUnavailableView {
                Label("Loading \(code)", systemImage: "arrow.triangle.2.circlepath")
            } description: {
                Text("Refreshing matches and calculating team OPR values…")
            } actions: {
                ProgressView()
                    .controlSize(.small)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Event Could Not Be Loaded", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
                    .textSelection(.enabled)
            } actions: {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        default:
            ContentUnavailableView {
                Label("Load an FTC Event", systemImage: "magnifyingglass")
            } description: {
                Text("Enter an event code in the toolbar and press Return to view rankings, highlights, and match history.")
            }
        }
    }
}
