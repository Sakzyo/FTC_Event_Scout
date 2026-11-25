import SwiftUI
import UniformTypeIdentifiers

/// The manual event editor: a match list beside the selected match's score form.
/// Every change saves immediately; rankings and charts refresh a moment later.
struct ManualMatchEntryView: View {
    @Bindable var model: AppModel
    let event: ManualEvent
    @State private var selection: ManualMatch.ID?
    @State private var isImporting = false
    @State private var importKind: ImportKind = .csvMerge
    @State private var isConfirmingReplace = false
    @State private var importReport: ImportReport?
    @State private var export: CSVExport?
    @State private var scoutExport: ScoutFileExport?

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
            allowedContentTypes: importKind.contentTypes
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let outcome = switch importKind {
                    case .csvMerge: try model.importManualMatches(from: url, into: event.id, replacing: false)
                    case .csvReplace: try model.importManualMatches(from: url, into: event.id, replacing: true)
                    case .scoutFile: try model.mergeScoutFile(from: url, into: event.id)
                    }
                    importReport = ImportReport(filename: url.lastPathComponent, kind: importKind, outcome: outcome)
                    if let first = outcome.merge.changedMatchIDs.first { selection = first }
                } catch {
                    model.manualEventError = "\(url.lastPathComponent) could not be imported: \(error.localizedDescription)"
                }
            case .failure(let error):
                model.manualEventError = "The file could not be opened: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Replace all \(event.matches.count) matches?",
            isPresented: $isConfirmingReplace,
            titleVisibility: .visible
        ) {
            Button("Choose CSV and Replace", role: .destructive) {
                beginImport(.csvReplace)
            }
        } message: {
            Text("Every match in \(event.name) is replaced by the rows in the CSV you choose.")
        }
        .sheet(item: $importReport) { report in
            ImportReportSheet(report: report)
        }
        .csvExporter($export, onError: { model.manualEventError = $0 })
    }

    private func beginImport(_ kind: ImportKind) {
        importKind = kind
        isImporting = true
    }

    private func exportScoutFile() {
        do {
            scoutExport = try ScoutFileExport(event: event, scoutName: model.scoutName)
        } catch {
            model.manualEventError = "The scout file could not be created: \(error.localizedDescription)"
        }
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
                    Button("Merge Scout File…") { beginImport(.scoutFile) }
                    Button("Export Scout File…", action: exportScoutFile)
                    Divider()
                    Button("Import CSV (Add and Merge Matches)…") { beginImport(.csvMerge) }
                    Button("Import CSV (Replace All Matches)…") {
                        if event.matches.isEmpty {
                            beginImport(.csvReplace)
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
                    Label("Import & Export", systemImage: "arrow.up.arrow.down")
                }
                .fixedSize()
                .help("Merge other scouts' files, or import and export matches as CSV")
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
                    Button("Import CSV…") { beginImport(.csvMerge) }
                    Button("Merge Scout File…") { beginImport(.scoutFile) }
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
        .scoutFileExporter($scoutExport, onError: { model.manualEventError = $0 })
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

private enum ImportKind {
    case csvMerge
    case csvReplace
    case scoutFile

    var contentTypes: [UTType] {
        self == .scoutFile ? [.json] : [.commaSeparatedText, .plainText]
    }
}

private struct ImportReport: Identifiable {
    let id = UUID()
    let filename: String
    let kind: ImportKind
    let outcome: ManualImportOutcome
}

private struct ImportReportSheet: View {
    let report: ImportReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let issues = report.outcome.issues
        let notes = report.outcome.merge.notes
        let needsAttention = !issues.isEmpty || notes.contains(where: \.needsReview)

        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: needsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(needsAttention ? Color.orange : Color.green)

            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !issues.isEmpty {
                Text("Skipped rows")
                    .font(.headline)
                List(issues) { issue in
                    HStack(alignment: .firstTextBaseline) {
                        Text("Line \(issue.line)")
                            .font(.scoutNumeric(size: 12, weight: .semibold))
                            .frame(width: 64, alignment: .leading)
                        Text(issue.message)
                            .textSelection(.enabled)
                    }
                }
                .frame(minHeight: 120, maxHeight: 220)
            }

            if !notes.isEmpty {
                Text("Entries both sides recorded differently")
                    .font(.headline)
                List(notes) { note in
                    MergeNoteRow(note: note)
                }
                .frame(minHeight: 140, maxHeight: 280)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var title: String {
        let merge = report.outcome.merge
        if report.kind == .csvReplace {
            return "Imported \(matchCount(merge.addedCount))"
        }
        if merge.addedCount == 0 && merge.updatedCount == 0 {
            return "No new entries"
        }
        var parts: [String] = []
        if merge.addedCount > 0 { parts.append("added \(matchCount(merge.addedCount))") }
        if merge.updatedCount > 0 { parts.append("updated \(matchCount(merge.updatedCount))") }
        let text = parts.joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private var detail: String {
        var text = "From \(report.filename)."
        if report.outcome.usedMatchDetailsFormat {
            text += " This is a FIRST Events Match Details file, so its matches were added as totals only."
        }
        if report.kind != .csvReplace {
            text += " Matches pair up by number; within each, the newer entry for every alliance, team, and the flowers is kept. Blank entries never replace recorded ones."
        }
        if report.kind == .csvMerge {
            text += " CSV rows carry no edit times, so they fill gaps but do not replace entries already here."
        }
        return text
    }

    private func matchCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "match" : "matches")"
    }
}

private struct MergeNoteRow: View {
    let note: ManualEventMerge.Note

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: note.needsReview ? "exclamationmark.triangle.fill" : "arrow.triangle.merge")
                .foregroundStyle(note.needsReview ? Color.orange : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(note.matchTitle) · \(note.piece.title)")
                    .font(.callout.weight(.semibold))
                Text(note.reviewReason ?? outcome)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }

    private var outcome: String {
        let keptSide = note.kept == .incoming ? "the file’s" : "this Mac’s"
        let otherSide = note.kept == .incoming ? "this Mac’s" : "the file’s"
        return "Kept \(keptSide) entry (\(describe(note.keptEdit))) over \(otherSide) (\(describe(note.replacedEdit)))."
    }

    private func describe(_ edit: ManualEdit?) -> String {
        guard let edit else { return "no edit time" }
        let time = edit.at.formatted(date: .omitted, time: .shortened)
        return "\(edit.by ?? "unnamed scout"), \(time)"
    }
}
