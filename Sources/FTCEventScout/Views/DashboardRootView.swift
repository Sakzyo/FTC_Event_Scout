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
                Divider()
                switch selection {
                case .rankings:
                    RankingsView(
                        model: model,
                        event: event,
                        present: presentRankingContent
                    )
                case .predictions:
                    MatchPredictionsView(event: event)
                case .highlights:
                    HighlightsView(model: model, event: event)
                }
            } else {
                EmptyDashboardView(loadState: model.eventLoadState, retry: model.refreshEvent)
            }
        }
        .navigationTitle(model.currentEvent?.eventCode ?? "Event")
    }
}

private struct EventHeaderView: View {
    let event: EventData
    let loadState: EventLoadState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        HUDModeBadge(mode: event.mode)
                        if !event.eventName.isEmpty {
                            Text(verbatim: event.eventCode)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .tracking(0.6)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .hudPanel(cornerRadius: 5)
                                .textSelection(.enabled)
                        }
                        Text(verbatim: FTCSeason.option(for: event.season).yearRange)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text(event.eventName.isEmpty ? event.eventCode : event.eventName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                }

                Spacer(minLength: 12)

                if case .loading(let code) = loadState {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        HUDLabel("SYNCING \(code)")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Refreshing \(code)")
                }
            }

            HStack(spacing: 8) {
                ForEach(event.overviewStats) { stat in
                    EventStatTile(stat: stat)
                }
            }

            if event.mode == .preview {
                Label(event.statusMessage, systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }
}

private struct EventStatTile: View {
    let stat: EventOverviewStat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HUDLabel(stat.label)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                NumericValueView(value: stat.value, fractionLength: stat.fractionLength)
                    .font(.hudNumeric(size: 20, weight: .medium))
                    .contentTransition(.numericText())
                if let detail = stat.detail {
                    Text(verbatim: detail)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel()
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
