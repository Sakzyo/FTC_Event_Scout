import SwiftUI
import UniformTypeIdentifiers

/// The manual event editor: a match list beside the selected match's score form.
/// Every change saves immediately; rankings and charts refresh a moment later.
struct ManualMatchEntryView: View {
    @Bindable var model: AppModel
    let event: ManualEvent
    @State private var selection: ManualMatch.ID?
    @State private var isImporting = false
    @State private var importReplaces = false
    @State private var isConfirmingReplace = false
    @State private var importReport: ImportReport?
    @State private var export: CSVExport?

    var body: some View {
        HSplitView {
            matchList
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 520, maxHeight: .infinity)
            editor
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selection == nil { selection = event.sortedMatches.first?.id }
        }
        .onChange(of: event.id) { _, _ in
            selection = event.sortedMatches.first?.id
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let result = try model.importManualMatches(from: url, into: event.id, replacing: importReplaces)
                    importReport = ImportReport(filename: url.lastPathComponent, result: result)
                    if let first = result.matches.first { selection = first.id }
                } catch {
                    model.manualEventError = "\(url.lastPathComponent) could not be imported: \(error.localizedDescription)"
                }
            case .failure(let error):
                model.manualEventError = "The CSV could not be opened: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Replace all \(event.matches.count) matches?",
            isPresented: $isConfirmingReplace,
            titleVisibility: .visible
        ) {
            Button("Choose CSV and Replace", role: .destructive) {
                importReplaces = true
                isImporting = true
            }
        } message: {
            Text("Every match in \(event.name) is replaced by the rows in the CSV you choose.")
        }
        .sheet(item: $importReport) { report in
            ImportReportSheet(report: report)
        }
        .csvExporter($export, onError: { model.manualEventError = $0 })
    }

    // MARK: Match list

    private var matchList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: addMatch) {
                    Label("Add Match", systemImage: "plus")
                }
                .help("Add the next match")

                Button(action: deleteSelectedMatch) {
                    Label("Delete", systemImage: "minus")
                        .labelStyle(.iconOnly)
                }
                .disabled(selection == nil)
                .help("Delete the selected match (⌫)")

                Spacer()

                Menu {
                    Button("Import CSV (Add Matches)…") {
                        importReplaces = false
                        isImporting = true
                    }
                    Button("Import CSV (Replace All Matches)…") {
                        if event.matches.isEmpty {
                            importReplaces = true
                            isImporting = true
                        } else {
                            isConfirmingReplace = true
                        }
                    }
                    Divider()
                    Button("Export CSV…") {
                        export = CSVExport(file: CSVFile(text: ManualEventCSV.export(event)), filename: event.name)
                    }
                    Button("Export Empty Template…") {
                        export = CSVExport(
                            file: CSVFile(text: ManualEventCSV.template(season: event.season)),
                            filename: "\(event.name) Template"
                        )
                    }
                } label: {
                    Label("CSV", systemImage: "tablecells.badge.ellipsis")
                }
                .fixedSize()
                .help("Import or export matches as CSV")
            }
            .padding(10)

            Divider()

            if event.matches.isEmpty {
                ContentUnavailableView {
                    Label("No Matches Yet", systemImage: "tablecells")
                } description: {
                    Text("Add matches one at a time, or import a CSV. FTC Event Scout's own Match Details CSVs import too.")
                } actions: {
                    Button("Add Match", action: addMatch)
                        .buttonStyle(.borderedProminent)
                    Button("Import CSV…") {
                        importReplaces = false
                        isImporting = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(event.sortedMatches) { match in
                        ManualMatchRow(match: match, event: event)
                            .tag(match.id)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds(.disabled)
                .onDeleteCommand(perform: deleteSelectedMatch)
            }
        }
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if let selection, let match = event.matches.first(where: { $0.id == selection }) {
            ManualMatchEditor(
                match: matchBinding(id: match.id, fallback: match),
                event: event,
                onNext: { advance(from: match.id) }
            )
            .id(match.id)
        } else {
            ContentUnavailableView {
                Label("No Match Selected", systemImage: "square.and.pencil")
            } description: {
                Text("Select a match in the list to enter its teams and score.")
            }
        }
    }

    private func matchBinding(id: UUID, fallback: ManualMatch) -> Binding<ManualMatch> {
        Binding(
            get: { model.activeManualEvent?.matches.first { $0.id == id } ?? fallback },
            set: { updated in
                guard var current = model.activeManualEvent,
                      let index = current.matches.firstIndex(where: { $0.id == id }) else { return }
                current.matches[index] = updated
                model.updateManualEvent(current)
            }
        )
    }

    // MARK: Actions

    private func addMatch() {
        guard var current = model.activeManualEvent else { return }
        let previous = current.matches.first { $0.id == selection } ?? current.sortedMatches.last
        let match = current.nextMatch(after: previous)
        current.matches.append(match)
        model.updateManualEvent(current)
        selection = match.id
    }

    /// Moves to the following match, adding one when the selection is the last.
    private func advance(from id: UUID) {
        let sorted = event.sortedMatches
        if let index = sorted.firstIndex(where: { $0.id == id }), index + 1 < sorted.count {
            selection = sorted[index + 1].id
        } else {
            addMatch()
        }
    }

    private func deleteSelectedMatch() {
        guard var current = model.activeManualEvent, let selection else { return }
        let sorted = current.sortedMatches
        let index = sorted.firstIndex { $0.id == selection } ?? 0
        current.matches.removeAll { $0.id == selection }
        model.updateManualEvent(current)
        let remaining = current.sortedMatches
        self.selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
}

/// One match in the schedule, read like an ftcscout match table: the match code beside a
/// red line and a blue line, each with its teams and score. The winner's score is bold.
private struct ManualMatchRow: View {
    let match: ManualMatch
    let event: ManualEvent

    var body: some View {
        let issues = match.validationIssues(in: event)
        let scores = match.isScored ? ManualEventBuilder.scoreBreakdowns(for: match, season: event.season) : nil
        let red = scores?.red.finalScore
        let blue = scores?.blue.finalScore

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(match.shortTitle)
                    .font(.scoutNumeric(size: 13, weight: .bold))
                if !issues.isEmpty {
                    Label("Check", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(issues.joined(separator: "\n"))
                } else if scores == nil {
                    Text("Scheduled")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
            .frame(width: 62, alignment: .leading)

            VStack(spacing: 2) {
                allianceLine(.red, teams: match.redTeams, score: red, opponent: blue)
                allianceLine(.blue, teams: match.blueTeams, score: blue, opponent: red)
            }
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(issues: issues, red: red, blue: blue))
    }

    private func allianceLine(_ alliance: AllianceColor, teams: [Int], score: Double?, opponent: Double?) -> some View {
        let isWinner = (score ?? 0) >= (opponent ?? 0) && score != nil
        return HStack(spacing: 0) {
            ForEach(0 ..< 2, id: \.self) { index in
                Text(index < teams.count ? teams[index].teamNumberText : "—")
                    .foregroundStyle(index < teams.count ? .primary : .tertiary)
                    .frame(width: 58, alignment: .leading)
            }
            Spacer(minLength: 6)
            Text(score.map { String(Int($0)) } ?? "—")
                .fontWeight(isWinner ? .bold : .regular)
                .foregroundStyle(score == nil ? .tertiary : isWinner ? .primary : .secondary)
        }
        .font(.scoutNumeric(size: 12))
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(alliance.scoutTone.opacity(0.15))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(alliance.scoutTone)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func accessibilityText(issues: [String], red: Double?, blue: Double?) -> String {
        var text = "\(match.title). Red \(teamList(match.redTeams)), blue \(teamList(match.blueTeams))."
        if let red, let blue {
            text += " Red \(Int(red)), blue \(Int(blue))."
        } else {
            text += " Scheduled."
        }
        if !issues.isEmpty { text += " Needs checking." }
        return text
    }

    private func teamList(_ teams: [Int]) -> String {
        teams.isEmpty ? "no teams" : teams.map(\.teamNumberText).joined(separator: " and ")
    }
}

// MARK: - Import report

private struct ImportReport: Identifiable {
    let id = UUID()
    let filename: String
    let result: ManualEventCSV.ImportResult
}

private struct ImportReportSheet: View {
    let report: ImportReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: report.result.issues.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(report.result.issues.isEmpty ? Color.green : Color.orange)

            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !report.result.issues.isEmpty {
                Text("Skipped rows")
                    .font(.headline)
                List(report.result.issues) { issue in
                    HStack(alignment: .firstTextBaseline) {
                        Text("Line \(issue.line)")
                            .font(.scoutNumeric(size: 12, weight: .semibold))
                            .frame(width: 64, alignment: .leading)
                        Text(issue.message)
                            .textSelection(.enabled)
                    }
                }
                .frame(minHeight: 140, maxHeight: 260)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var title: String {
        let count = report.result.matches.count
        return "Imported \(count) \(count == 1 ? "match" : "matches")"
    }

    private var detail: String {
        var text = "From \(report.filename)."
        if report.result.usedMatchDetailsFormat {
            text += " This is a FIRST Events Match Details file, so its matches were added as totals only."
        }
        return text
    }
}
