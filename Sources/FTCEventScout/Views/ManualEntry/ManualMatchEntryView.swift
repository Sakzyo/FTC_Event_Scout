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
            } else {
                Table(event.sortedMatches, selection: $selection) {
                    TableColumn("Match") { match in
                        Text(match.shortTitle)
                            .font(.scoutNumeric(size: 12, weight: .semibold))
                    }
                    .width(min: 44, ideal: 52, max: 70)
                    TableColumn("Red") { match in
                        teamText(match.redTeams)
                            .foregroundStyle(AllianceColor.red.displayColor)
                    }
                    TableColumn("Blue") { match in
                        teamText(match.blueTeams)
                            .foregroundStyle(AllianceColor.blue.displayColor)
                    }
                    TableColumn("Score") { match in
                        ManualMatchStatusText(match: match, event: event)
                    }
                    .width(min: 72, ideal: 88)
                }
                .onDeleteCommand(perform: deleteSelectedMatch)
            }
        }
    }

    private func teamText(_ teams: [Int]) -> Text {
        Text(teams.isEmpty ? "—" : teams.map(\.teamNumberText).joined(separator: " · "))
            .font(.scoutNumeric(size: 12))
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

private struct ManualMatchStatusText: View {
    let match: ManualMatch
    let event: ManualEvent

    var body: some View {
        if !match.validationIssues(in: event).isEmpty {
            Label("Check", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .help(match.validationIssues(in: event).joined(separator: "\n"))
        } else if match.isScored {
            let scores = ManualEventBuilder.scoreBreakdowns(for: match, season: event.season)
            HStack(spacing: 3) {
                Text(scoreText(scores.red.finalScore))
                    .foregroundStyle(AllianceColor.red.displayColor)
                Text("–").foregroundStyle(.secondary)
                Text(scoreText(scores.blue.finalScore))
                    .foregroundStyle(AllianceColor.blue.displayColor)
            }
            .font(.scoutNumeric(size: 12, weight: .semibold))
        } else {
            Text("Scheduled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func scoreText(_ value: Double?) -> String {
        value.map { String(Int($0)) } ?? "—"
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
