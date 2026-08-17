import SwiftUI

struct DashboardRootView: View {
    @Bindable var model: AppModel
    @SceneStorage("selectedDashboardSection") private var selectedSectionRaw: String? = DashboardSection.rankings.rawValue

    private var selectedSection: DashboardSection {
        DashboardSection(rawValue: selectedSectionRaw ?? "") ?? .rankings
    }

    var body: some View {
        NavigationSplitView {
            DashboardSidebar(model: model, selection: $selectedSectionRaw)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            DashboardDetail(model: model, selection: selectedSection)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct DashboardSidebar: View {
    @Bindable var model: AppModel
    @Binding var selection: String?

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
                    Text(event.mode == .preview ? "Historical preview" : "Live event data")
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
        case .highlights:
            Label("Highlights", systemImage: "trophy")
        }
    }
}

private struct DashboardDetail: View {
    @Bindable var model: AppModel
    let selection: DashboardSection

    var body: some View {
        VStack(spacing: 0) {
            if let event = model.currentEvent {
                EventHeaderView(event: event, loadState: model.eventLoadState)
                Divider()
                switch selection {
                case .rankings:
                    RankingsView(model: model, event: event)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.eventName.isEmpty ? event.eventCode : event.eventName)
                        .font(.title2.weight(.semibold))
                    if !event.eventName.isEmpty {
                        Text(event.eventCode)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(event.mode == .preview ? "PREVIEW" : "CURRENT")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(event.mode == .preview ? .orange : .secondary)
            }

            switch loadState {
            case .loading(let code):
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing \(code)…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            default:
                StatusBannerView(message: event.statusMessage, kind: .success)
            }
        }
        .padding(16)
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
