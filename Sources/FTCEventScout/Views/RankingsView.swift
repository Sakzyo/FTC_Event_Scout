import SwiftUI

struct RankingsView: View {
    @Bindable var model: AppModel
    let event: EventData
    @State private var presentedSheet: RankingSheet?

    var body: some View {
        VStack(spacing: 0) {
            RankingsControls(model: model)
            Divider()

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
                    presentedSheet: $presentedSheet
                )
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
            Text("\(model.rankedStandings.count) teams")
                .font(.callout)
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
                    .monospacedDigit()
            }
            .width(min: 52, ideal: 58, max: 72)

            TableColumn("Rank") { row in
                Text(row.team.storedRank.formatted())
                    .monospacedDigit()
            }
            .width(min: 48, ideal: 56, max: 70)

            TableColumn("Team") { row in
                Button(row.team.teamNumber.formatted()) {
                    presentedSheet = .matches(eventCode: eventCode, teamNumber: row.team.teamNumber)
                }
                .buttonStyle(.link)
                .accessibilityLabel("Team \(row.team.teamNumber), show match history")
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
            }
            .width(min: 70, ideal: 86, max: 110)

            TableColumn("npOPR") { row in
                NumericValueView(value: row.team.nonPenaltyOPR, fractionDigits: 2)
            }
            .width(min: 70, ideal: 86, max: 110)

            TableColumn("Auto") { row in
                NumericValueView(value: row.team.autoOPR, fractionDigits: 2)
            }
            .width(min: 70, ideal: 86, max: 110)

            TableColumn("Teleop") { row in
                NumericValueView(value: row.team.teleopOPR, fractionDigits: 2)
            }
            .width(min: 70, ideal: 86, max: 110)

            TableColumn("Endgame") { row in
                NumericValueView(value: row.team.endgameOPR, fractionDigits: 2)
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
    @Binding var presentedSheet: RankingSheet?

    var body: some View {
        Table(rows) {
            TableColumn("Rank") { row in
                Text(row.order.formatted())
                    .monospacedDigit()
            }
            .width(min: 48, ideal: 56, max: 70)

            TableColumn("Team") { row in
                Text(row.team.teamNumber.formatted())
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
            }
            .width(min: 92, ideal: 110, max: 130)

            TableColumn("Best Season") { row in
                OptionalIntegerValue(value: row.team.bestSeason)
            }
            .width(min: 82, ideal: 96, max: 110)

            TableColumn("2025") { row in
                NumericValueView(value: row.team.perSeason["2025"]?.total, fractionDigits: 2)
            }
            .width(min: 66, ideal: 78, max: 96)

            TableColumn("2024") { row in
                NumericValueView(value: row.team.perSeason["2024"]?.total, fractionDigits: 2)
            }
            .width(min: 66, ideal: 78, max: 96)

            TableColumn("2023") { row in
                NumericValueView(value: row.team.perSeason["2023"]?.total, fractionDigits: 2)
            }
            .width(min: 66, ideal: 78, max: 96)

            TableColumn("Rookie Year") { row in
                OptionalIntegerValue(value: row.team.rookieYear)
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
