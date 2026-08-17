import SwiftUI

struct HighlightsView: View {
    @Bindable var model: AppModel
    let event: EventData

    private let columns = [
        GridItem(.flexible(minimum: 260), spacing: 12),
        GridItem(.flexible(minimum: 260), spacing: 12),
    ]

    var body: some View {
        if event.mode == .preview {
            ContentUnavailableView {
                Label("No Match Highlights Yet", systemImage: "trophy")
            } description: {
                Text("This event has not started. Highlights will appear after match scores are available.")
            }
        } else if event.highlights.allSatisfy({ $0.entries.isEmpty }) {
            ContentUnavailableView(
                "No Match Highlights",
                systemImage: "trophy",
                description: Text("No scored matches are available for this event.")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(event.highlights) { highlight in
                        HighlightCardView(
                            model: model,
                            eventCode: event.eventCode,
                            highlight: highlight
                        )
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct HighlightCardView: View {
    @Bindable var model: AppModel
    let eventCode: String
    let highlight: EventHighlight

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    NumericValueView(value: highlight.score, fractionDigits: 1)
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Spacer()
                    Text(noteText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                Divider()

                if highlight.entries.isEmpty {
                    Text("No score is available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(highlight.entries) { entry in
                        HighlightEntryView(
                            model: model,
                            eventCode: eventCode,
                            entry: entry
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            HighlightMetricLabel(metric: highlight.metric)
        }
    }

    private var noteText: String {
        if highlight.entries.count == 1 { return "Top alliance" }
        if highlight.entries.isEmpty { return "Unavailable" }
        return "\(highlight.entries.count) alliances tied"
    }
}

private struct HighlightMetricLabel: View {
    let metric: HighlightMetric

    var body: some View {
        switch metric {
        case .final:
            Label("Highest Final Score", systemImage: "flag.checkered")
        case .nonPenalty:
            Label("Highest Non-Penalty Score", systemImage: "equal.circle")
        case .auto:
            Label("Highest Auto Score", systemImage: "bolt")
        case .teleop:
            Label("Highest Teleop Score", systemImage: "gamecontroller")
        }
    }
}

private struct HighlightEntryView: View {
    @Bindable var model: AppModel
    let eventCode: String
    let entry: HighlightEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.match.displayTitle)
                    .font(.headline)
                Spacer()
                Label(
                    entry.alliance == .red ? "Red Alliance" : "Blue Alliance",
                    systemImage: "circle.fill"
                )
                .font(.caption)
                .foregroundStyle(entry.alliance == .red ? .red : .blue)
            }

            HStack(spacing: 12) {
                ForEach(entry.teams, id: \.self) { teamNumber in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Team \(teamNumber.teamNumberText)")
                            .font(.callout.weight(.medium))
                        TeamTagsSummaryView(
                            tags: model.tags(eventCode: eventCode, teamNumber: teamNumber)
                        )
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }
}
