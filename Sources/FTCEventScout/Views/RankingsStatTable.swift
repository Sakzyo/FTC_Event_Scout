import SwiftUI

/// One column of the Rankings stat table. Columns are grouped by color, as on ftcscout.org:
/// identity in white, match results and history in blue, and OPR estimates in red.
enum RankingColumn: Hashable, Identifiable {
    case order
    case eventRank
    case team
    case tags
    case record
    case played
    case metric(RankingSortField)
    case bestSeason
    case seasonOPR(Int)
    case rookieYear

    var id: Self { self }

    static let liveMetrics: [RankingSortField] = [
        .totalOPR, .oprc, .nonPenaltyOPR, .autoOPR, .teleopOPR, .endgameOPR,
    ]

    static func live(sortField: RankingSortField) -> [RankingColumn] {
        // When sorting by event rank the display position repeats it, so leave it out.
        let leading: [RankingColumn] = sortField == .storedRank ? [] : [.order]
        return leading + [.eventRank, .team, .tags, .record, .played] + liveMetrics.map { .metric($0) }
    }

    static func preview(season: Int) -> [RankingColumn] {
        [
            .order, .team, .tags, .metric(.highestOPR), .bestSeason,
            .seasonOPR(season), .seasonOPR(season - 1), .seasonOPR(season - 2), .rookieYear,
        ]
    }

    var title: String {
        switch self {
        case .order: "#"
        case .eventRank: "Rank"
        case .team: "Team"
        case .tags: "Tags"
        case .record: "Record"
        case .played: "Played"
        case .metric(let field): Self.metricTitle(field)
        case .bestSeason: "Best Season"
        case .seasonOPR(let season): String(season)
        case .rookieYear: "Rookie Year"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .order: "Position"
        case .eventRank: "Event rank"
        case .record: "Qualification record"
        case .played: "Matches played"
        case .metric(.oprc): "Calculated OPR"
        case .metric(.nonPenaltyOPR): "Non-penalty OPR"
        case .metric(.autoOPR): "Auto OPR"
        case .metric(.teleopOPR): "Teleop OPR"
        case .metric(.endgameOPR): "Endgame OPR"
        case .seasonOPR(let season): "\(season) season OPR"
        default: title
        }
    }

    var color: ScoutStatColor {
        switch self {
        case .order, .eventRank, .team, .tags: .white
        case .record, .played, .rookieYear: .blue
        case .metric(.highestOPR): .blue
        case .bestSeason: .lightBlue
        case .metric, .seasonOPR: .red
        }
    }

    /// The field a header click sorts by. Position, tags, and single seasons don't sort.
    var sortField: RankingSortField? {
        switch self {
        case .order, .tags, .seasonOPR: nil
        case .eventRank: .storedRank
        case .team: .teamNumber
        case .record: .record
        case .played: .played
        case .metric(let field): field
        case .bestSeason: .bestSeason
        case .rookieYear: .rookieYear
        }
    }

    var help: String? {
        switch self {
        case .eventRank: "Official event ranking"
        case .record: "Qualification wins-losses-ties"
        case .played: "Qualification matches played"
        case .metric(.totalOPR): "Offensive power rating"
        case .metric(.oprc): "Calculated OPR after one residual-IQR outlier filtering pass"
        case .metric(.nonPenaltyOPR): "OPR without points from opponent penalties"
        case .metric(.highestOPR): "Highest OPR across past seasons"
        case .seasonOPR(let season): "Best OPR in the \(season) season"
        default: nil
        }
    }

    /// The narrowest comfortable width. Extra room is shared by every column except the position and tags.
    func baseWidth(showsTeamNames: Bool) -> CGFloat {
        switch self {
        case .order: 44
        case .eventRank: 64
        case .team: showsTeamNames ? 176 : 92
        case .tags: 116
        case .record: 84
        case .played: 72
        case .metric(.highestOPR): 108
        case .metric: 82
        case .bestSeason: 104
        case .seasonOPR: 74
        case .rookieYear: 104
        }
    }

    var isFlexible: Bool { self != .order && self != .tags }

    /// Magnitude columns draw a scale bar under each cell while they're the sort column.
    var showsScaleBar: Bool {
        switch self {
        case .record, .played, .metric, .seasonOPR: true
        default: false
        }
    }

    var alignment: Alignment {
        self == .team || self == .tags ? .leading : .center
    }

    /// Shared by the header and body cells so leading-aligned titles sit over their values.
    var horizontalInset: CGFloat {
        switch self {
        case .team: 12
        case .tags: 8
        default: 6
        }
    }

    func value(
        for row: RankedStanding,
        records: [Int: TeamEventRecord],
        metrics: [Int: TeamOPRcMetric]
    ) -> RankingCellValue {
        let team = row.team
        switch self {
        case .order: return .position(row.order)
        case .eventRank: return .ordinal(team.storedRank)
        case .team: return .team(number: team.teamNumber, name: team.teamName)
        case .tags: return .tags
        case .record:
            let record = records[team.teamNumber]
            return .record((record?.played ?? 0) > 0 ? record : nil)
        case .played: return .count(records[team.teamNumber]?.played ?? 0)
        case .metric(.oprc): return .decimal(metrics[team.teamNumber]?.oprc)
        case .metric(let field): return .decimal(Self.metricValue(field, for: team))
        case .bestSeason: return .year(team.bestSeason)
        case .seasonOPR(let season): return .decimal(team.perSeason[String(season)]?.total)
        case .rookieYear: return .year(team.rookieYear)
        }
    }

    private static func metricTitle(_ field: RankingSortField) -> String {
        switch field {
        case .totalOPR: "OPR"
        case .oprc: "OPRc"
        case .nonPenaltyOPR: "npOPR"
        case .autoOPR: "Auto"
        case .teleopOPR: "Teleop"
        case .endgameOPR: "Endgame"
        case .highestOPR: "Highest OPR"
        default: field.rawValue
        }
    }

    private static func metricValue(_ field: RankingSortField, for team: TeamStanding) -> Double? {
        switch field {
        case .totalOPR: team.totalOPR
        case .nonPenaltyOPR: team.nonPenaltyOPR
        case .autoOPR: team.autoOPR
        case .teleopOPR: team.teleopOPR
        case .endgameOPR: team.endgameOPR
        case .highestOPR: team.highestOPR
        default: nil
        }
    }
}

enum RankingCellValue: Equatable {
    case position(Int)
    case ordinal(Int)
    case team(number: Int, name: String)
    case tags
    case decimal(Double?)
    case year(Int?)
    case record(TeamEventRecord?)
    case count(Int)

    /// Spoken form for the row summary; identity cells are announced separately.
    var accessibilityText: String? {
        switch self {
        case .position(let position): String(position)
        case .ordinal(let rank): ScoutFormat.ordinal(rank)
        case .team, .tags: nil
        case .decimal(let value): value?.formatted(.number.precision(.fractionLength(2))) ?? "Unavailable"
        case .year(let year): year.map(String.init) ?? "Unavailable"
        case .record(let record): record?.accessibilityText ?? "Unavailable"
        case .count(let count): String(count)
        }
    }

    /// The quantity a scale bar measures. Records use their win rate, which is what they sort by.
    var magnitude: Double? {
        switch self {
        case .decimal(let value): value
        case .record(let record): record?.winRate
        case .count(let count): Double(count)
        default: nil
        }
    }
}

/// Sizes the scale bars of the sorted column against that column's largest value.
struct RankingColumnScale: Equatable {
    let column: RankingColumn
    private let maximum: Double

    init?(
        sortField: RankingSortField,
        columns: [RankingColumn],
        rows: [RankedStanding],
        records: [Int: TeamEventRecord],
        metrics: [Int: TeamOPRcMetric]
    ) {
        guard let column = columns.first(where: { $0.sortField == sortField }),
              column.showsScaleBar else {
            return nil
        }
        self.column = column
        maximum = rows
            .compactMap { column.value(for: $0, records: records, metrics: metrics).magnitude }
            .filter(\.isFinite)
            .max() ?? 0
    }

    /// The bar length from 0 to 1. Negative and unavailable values get an empty track.
    func fraction(for value: RankingCellValue) -> Double {
        guard let magnitude = value.magnitude, magnitude.isFinite, magnitude > 0, maximum > 0 else {
            return 0
        }
        return min(magnitude / maximum, 1)
    }
}

/// Column widths that fill the available width, like ftcscout's `min-width: 100%` table.
struct RankingColumnLayout: Equatable {
    private let widths: [RankingColumn: CGFloat]
    let totalWidth: CGFloat

    init(columns: [RankingColumn], availableWidth: CGFloat, showsTeamNames: Bool) {
        let base = columns.map { ($0, $0.baseWidth(showsTeamNames: showsTeamNames)) }
        let baseTotal = base.reduce(0) { $0 + $1.1 }
        let flexibleTotal = base.filter { $0.0.isFlexible }.reduce(0) { $0 + $1.1 }
        let extra = max(availableWidth - baseTotal, 0)

        var widths: [RankingColumn: CGFloat] = [:]
        for (column, width) in base {
            let share = column.isFlexible && flexibleTotal > 0 ? extra * width / flexibleTotal : 0
            widths[column] = width + share
        }
        self.widths = widths
        totalWidth = baseTotal + (flexibleTotal > 0 ? extra : 0)
    }

    func width(for column: RankingColumn) -> CGFloat {
        widths[column] ?? 0
    }
}

// MARK: - Table

/// The ftcscout-style stats table: color-grouped columns, a pinned sortable header,
/// zebra rows, scale bars under the sorted column, and an accent outline on the hovered row.
/// Clicking a row opens match history.
struct RankingsStatTable: View {
    @Bindable var model: AppModel
    let event: EventData
    let present: (RankingPresentation) -> Void

    private var columns: [RankingColumn] {
        switch event.mode {
        case .live: RankingColumn.live(sortField: model.sortField)
        case .preview: RankingColumn.preview(season: event.season)
        }
    }

    private var showsTeamNames: Bool {
        event.standings.contains { !$0.teamName.isEmpty }
    }

    var body: some View {
        let columns = columns
        let showsTeamNames = showsTeamNames
        let rowHeight: CGFloat = showsTeamNames ? 44 : 34
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let rows = model.rankedStandings
        let scale = RankingColumnScale(
            sortField: model.sortField,
            columns: columns,
            rows: rows,
            records: event.teamRecords,
            metrics: event.oprcAnalysis.teamMetrics
        )

        GeometryReader { proxy in
            let layout = RankingColumnLayout(
                columns: columns,
                availableWidth: proxy.size.width,
                showsTeamNames: showsTeamNames
            )

            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(rows) { row in
                            RankingStatRow(
                                row: row,
                                columns: columns,
                                layout: layout,
                                rowHeight: rowHeight,
                                records: event.teamRecords,
                                metrics: event.oprcAnalysis.teamMetrics,
                                sortField: model.sortField,
                                scale: scale,
                                tags: model.tags(eventCode: event.eventCode, teamNumber: row.team.teamNumber),
                                showMatches: {
                                    present(.matches(eventCode: event.eventCode, teamNumber: row.team.teamNumber))
                                },
                                editTags: {
                                    present(.tags(eventCode: event.eventCode, teamNumber: row.team.teamNumber))
                                }
                            )
                        }
                    } header: {
                        RankingHeaderRow(
                            columns: columns,
                            layout: layout,
                            sortField: model.sortField,
                            sortDirection: model.sortDirection,
                            sort: model.sortByColumn
                        )
                    }
                }
                .frame(width: layout.totalWidth, alignment: .leading)
            }
        }
        .background(.scoutCard)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.scoutSeparator, lineWidth: 1))
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No Teams",
                    systemImage: "person.3",
                    description: Text("Teams will appear once the event roster is available.")
                )
            }
        }
    }
}

struct RankingHeaderRow: View {
    let columns: [RankingColumn]
    let layout: RankingColumnLayout
    let sortField: RankingSortField
    let sortDirection: SortDirection
    let sort: (RankingSortField) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                RankingHeaderCell(
                    column: column,
                    width: layout.width(for: column),
                    activeDirection: column.sortField == sortField ? sortDirection : nil,
                    sort: column.sortField.map { field in { sort(field) } }
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.scoutSeparator)
                .frame(height: 1)
        }
    }
}

private struct RankingHeaderCell: View {
    let column: RankingColumn
    let width: CGFloat
    let activeDirection: SortDirection?
    let sort: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        if let sort {
            Button(action: sort) {
                label
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(helpText)
            .accessibilityLabel(column.accessibilityTitle)
            .accessibilityValue(sortState)
            .accessibilityHint("Sorts the table by this column.")
        } else {
            label
                .help(column.help ?? "")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(column.accessibilityTitle)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            Text(verbatim: column.title)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
            if sort != nil {
                RankingSortIndicator(direction: activeDirection, isHovering: isHovering)
            }
        }
        .foregroundStyle(column.color.headerText)
        .padding(.horizontal, column.horizontalInset)
        .frame(width: width, height: 38, alignment: column.alignment)
        .background(column.color.headerFill)
        .overlay(alignment: .bottom) {
            if column.color == .white {
                // ftcscout's inset shadow: a soft shade where white headers meet the rows.
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 5)
            }
        }
        .overlay(Color.primary.opacity(isHovering ? 0.06 : 0))
        .animation(.scoutHover, value: isHovering)
        .contentShape(Rectangle())
    }

    private var helpText: String {
        let action = activeDirection == nil ? "Click to sort" : "Click to reverse the sort"
        guard let help = column.help else { return action }
        return "\(help). \(action)."
    }

    private var sortState: String {
        switch activeDirection {
        case .ascending: "Sorted ascending"
        case .descending: "Sorted descending"
        case nil: "Not sorted"
        }
    }
}

/// Two stacked triangles; the one matching the active direction is solid.
private struct RankingSortIndicator: View {
    let direction: SortDirection?
    let isHovering: Bool

    var body: some View {
        let idle = isHovering ? 0.65 : 0.35
        VStack(spacing: 1.5) {
            Image(systemName: "arrowtriangle.up.fill")
                .opacity(direction == .ascending ? 1 : idle)
            Image(systemName: "arrowtriangle.down.fill")
                .opacity(direction == .descending ? 1 : idle)
        }
        .font(.system(size: 5.5, weight: .bold))
        .accessibilityHidden(true)
    }
}

struct RankingStatRow: View {
    let row: RankedStanding
    let columns: [RankingColumn]
    let layout: RankingColumnLayout
    let rowHeight: CGFloat
    let records: [Int: TeamEventRecord]
    let metrics: [Int: TeamOPRcMetric]
    let sortField: RankingSortField
    let scale: RankingColumnScale?
    let tags: [TeamTag]
    let showMatches: () -> Void
    let editTags: () -> Void
    @State private var isHovering = false

    var body: some View {
        interactiveRow
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: accessibilityLabel))
            .accessibilityValue(Text(verbatim: accessibilityValue))
            .accessibilityHint(Text("Shows match history."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, showMatches)
            .accessibilityAction(named: Text(tags.isEmpty ? "Add tag" : "Edit tags"), editTags)
    }

    private var interactiveRow: some View {
        let stripe = row.order.isMultiple(of: 2)
        return cells
            .background(stripe ? AnyShapeStyle(.scoutZebra) : AnyShapeStyle(.clear))
            .overlay(hoverOutline)
            .animation(.scoutHover, value: isHovering)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture(perform: showMatches)
            .help(Text(verbatim: helpText))
    }

    private var cells: some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                cell(for: column)
            }
        }
    }

    private func cell(for column: RankingColumn) -> some View {
        let value = column.value(for: row, records: records, metrics: metrics)
        let tint = column.color.cellTint
        return RankingCellView(
            value: value,
            isSorted: column.sortField == sortField,
            tags: tags,
            editTags: editTags
        )
        .padding(.horizontal, column.horizontalInset)
        .frame(width: layout.width(for: column), height: rowHeight, alignment: column.alignment)
        .overlay {
            if let scale, scale.column == column {
                // Offset from the cell's center so values keep their baseline across the row.
                ScoutScaleBar(
                    fraction: scale.fraction(for: value),
                    width: max(layout.width(for: column) - 24, 12),
                    tone: column.color.tone
                )
                .offset(y: 11.5)
            }
        }
        .background {
            if let tint {
                Rectangle().fill(tint)
            }
        }
    }

    private var hoverOutline: some View {
        Rectangle()
            .strokeBorder(.tint, lineWidth: 2)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(false)
    }

    private var helpText: String {
        "Show match history for Team " + row.team.teamNumber.teamNumberText
    }

    private var accessibilityLabel: String {
        let name = row.team.teamName
        return name.isEmpty
            ? "Team \(row.team.teamNumber.teamNumberText)"
            : "Team \(row.team.teamNumber.teamNumberText), \(name)"
    }

    private var accessibilityValue: String {
        var parts = columns.compactMap { column -> String? in
            column.value(for: row, records: records, metrics: metrics).accessibilityText
                .map { "\(column.accessibilityTitle) \($0)" }
        }
        if !tags.isEmpty {
            parts.append("Tags: " + tags.map(\.text).joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}

private struct RankingCellView: View {
    let value: RankingCellValue
    let isSorted: Bool
    let tags: [TeamTag]
    let editTags: () -> Void

    var body: some View {
        switch value {
        case .position(let position):
            Text(verbatim: String(position))
                .font(.scoutNumeric(size: 13))
                .foregroundStyle(.scoutSecondaryText)
        case .ordinal(let rank):
            Text(verbatim: ScoutFormat.ordinal(rank))
                .font(.scoutNumeric(size: 13, weight: .bold))
        case .team(let number, let name):
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: number.teamNumberText)
                    .font(.scoutNumeric(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)
                if !name.isEmpty {
                    Text(verbatim: name)
                        .font(.system(size: 11.5))
                        .italic()
                        .foregroundStyle(.scoutSecondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        case .tags:
            TeamTagsTableCell(tags: tags, edit: editTags)
        case .decimal(let value):
            if let value {
                Text(value, format: .number.precision(.fractionLength(2)))
                    .font(.scoutNumeric(size: 13, weight: isSorted ? .semibold : .regular))
            } else {
                NotAvailableText()
            }
        case .year(let year):
            if let year {
                Text(verbatim: String(year))
                    .font(.scoutNumeric(size: 13, weight: isSorted ? .semibold : .regular))
            } else {
                NotAvailableText()
            }
        case .record(let record):
            if let record {
                Text(verbatim: record.displayText)
                    .font(.scoutNumeric(size: 13, weight: isSorted ? .semibold : .regular))
            } else {
                NotAvailableText()
            }
        case .count(let count):
            Text(verbatim: String(count))
                .font(.scoutNumeric(size: 13, weight: isSorted ? .semibold : .regular))
        }
    }
}

private struct NotAvailableText: View {
    var body: some View {
        Text(verbatim: "N/A")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.scoutSecondaryText)
    }
}

private struct TeamTagsTableCell: View {
    let tags: [TeamTag]
    let edit: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 5) {
                if !tags.isEmpty {
                    TeamTagsSummaryView(tags: tags)
                }
                Image(systemName: "plus.circle")
                    .foregroundStyle(isHovering ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.scoutHover, value: isHovering)
        .help(tags.isEmpty ? "Add a team tag" : "Edit team tags")
        .accessibilityLabel(tags.isEmpty ? "Add team tag" : "Edit team tags")
    }
}
