import SwiftUI
import UniformTypeIdentifiers

/// Sidebar rows for switching between FIRST Events and manual events, with
/// rename, export, and delete on each manual event.
struct ManualEventSourceSection: View {
    @Bindable var model: AppModel
    @State private var renaming: ManualEvent?
    @State private var renameText = ""
    @State private var deleting: ManualEvent?
    @State private var export: CSVExport?

    var body: some View {
        Section("Data Source") {
            DataSourceRow(
                title: "FIRST Events",
                subtitle: onlineSubtitle,
                systemImage: "globe",
                isActive: !model.isManualSourceActive,
                action: model.showOnlineEvents
            )

            ForEach(sortedEvents) { event in
                DataSourceRow(
                    title: event.name,
                    subtitle: "\(FTCSeason.option(for: event.season).yearRange) · \(matchCountText(event))",
                    systemImage: "square.and.pencil",
                    isActive: model.activeManualEvent?.id == event.id,
                    action: { model.openManualEvent(id: event.id) }
                )
                .contextMenu {
                    Button("Rename…") {
                        renameText = event.name
                        renaming = event
                    }
                    Button("Export CSV…") {
                        export = CSVExport(
                            file: CSVFile(text: ManualEventCSV.export(event)),
                            filename: event.name
                        )
                    }
                    Divider()
                    Button("Delete…", role: .destructive) { deleting = event }
                }
            }

            Button(action: model.presentNewManualEvent) {
                Label("New Manual Event…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .help("Create an event and enter match data by hand (⇧⌘N)")
        }
        .alert(
            "Rename Manual Event",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let renaming { model.renameManualEvent(id: renaming.id, to: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "this event")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Event", role: .destructive) {
                if let deleting { model.deleteManualEvent(id: deleting.id) }
            }
        } message: {
            Text("Its \(deleting.map(matchCountText) ?? "matches") and team tags will be removed from this Mac. Export a CSV first to keep a copy.")
        }
        .csvExporter($export, onError: { model.manualEventError = $0 })
    }

    private var sortedEvents: [ManualEvent] {
        model.manualEvents.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var onlineSubtitle: String {
        guard model.isReady else { return "Add credentials in Settings" }
        let code = model.eventCode.trimmingCharacters(in: .whitespaces)
        return code.isEmpty ? "Enter an event code" : code
    }

    private func matchCountText(_ event: ManualEvent) -> String {
        event.matches.count == 1 ? "1 match" : "\(event.matches.count) matches"
    }
}

private struct DataSourceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .fontWeight(isActive ? .semibold : .regular)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isActive ? "\(subtitle), showing" : subtitle)
    }
}

// MARK: - New event

struct NewManualEventSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var season = BiobuzzScoring.season

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Manual Event")
                .font(.title2.weight(.semibold))
            Text("Enter match results yourself or import a CSV. Rankings, OPR charts, predictions, and highlights are calculated on this Mac, without FIRST Events credentials.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                TextField("Name", text: $name, prompt: Text("Saturday Scrimmage"))
                Picker("Season", selection: $season) {
                    ForEach(FTCSeason.supported) { option in
                        Text(option.startYear == BiobuzzScoring.season
                             ? option.menuLabel
                             : "\(option.menuLabel) · totals only")
                            .tag(option.startYear)
                    }
                }
            }

            Text(season == BiobuzzScoring.season
                 ? "BIOBUZZ matches record hive tips, robot leave and park, flowers, garden, and fouls; the app calculates every point."
                 : "Matches in this season record Auto, Driver-Controlled, Endgame, and penalty totals.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    model.createManualEvent(name: name, season: season)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

// MARK: - CSV files

struct CSVFile: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // A byte-order mark makes Excel read the file as UTF-8, matching the helper's CSVs.
        FileWrapper(regularFileWithContents: Data("\u{feff}\(text)".utf8))
    }
}

struct CSVExport {
    let file: CSVFile
    let filename: String
}

extension View {
    func csvExporter(_ export: Binding<CSVExport?>, onError: @escaping (String) -> Void) -> some View {
        fileExporter(
            isPresented: Binding(get: { export.wrappedValue != nil }, set: { if !$0 { export.wrappedValue = nil } }),
            document: export.wrappedValue?.file,
            contentType: .commaSeparatedText,
            defaultFilename: export.wrappedValue?.filename
        ) { result in
            if case .failure(let error) = result {
                onError("The CSV could not be saved: \(error.localizedDescription)")
            }
            export.wrappedValue = nil
        }
    }
}
