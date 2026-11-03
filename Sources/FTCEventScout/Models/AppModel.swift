import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum LaunchState: Equatable {
        case idle
        case credentialsRequired
        case starting
        case ready(BackendContext)
        case pythonRequired
        case failed(String)
    }

    /// Where `currentEvent` comes from: FIRST Events, or a manual event typed on this Mac.
    enum DataSource: Equatable {
        case online
        case manual(UUID)
    }

    var launchState: LaunchState = .idle
    var eventLoadState: EventLoadState = .empty
    var username: String
    var token: String
    var eventCode: String
    var selectedSeason: Int {
        didSet {
            guard selectedSeason != oldValue else { return }
            preferences.selectedSeason = selectedSeason
            handleSeasonChange()
        }
    }
    var settingsMessage: String?
    var sortField: RankingSortField {
        didSet {
            preferences.rankingSortField = sortField
            recomputeRankedStandings()
        }
    }
    var sortDirection: SortDirection {
        didSet {
            preferences.sortDirection = sortDirection
            recomputeRankedStandings()
        }
    }
    var rememberLastEvent: Bool {
        didSet {
            preferences.rememberLastEvent = rememberLastEvent
            if !rememberLastEvent {
                preferences.lastEventCode = ""
            }
        }
    }

    var oprChartLayout: OPRChartLayout {
        didSet {
            preferences.oprChartLayout = oprChartLayout
        }
    }

    private(set) var currentEvent: EventData?
    private(set) var rankedStandings: [RankedStanding] = []
    private(set) var storedTagGroups: [StoredTeamTags] = []
    private(set) var focusToken = 0
    private(set) var dataSource: DataSource = .online
    private(set) var manualEvents: [ManualEvent] = []
    var isPresentingNewManualEvent = false
    /// A manual-event save, load, or import failure to show the user.
    var manualEventError: String?

    @ObservationIgnored private let backendService = BackendService()
    @ObservationIgnored private let eventService = EventService()
    @ObservationIgnored private let tagStore = TagStore()
    @ObservationIgnored private let manualEventStore = ManualEventStore()
    @ObservationIgnored private var lastOnlineEvent: EventData?
    @ObservationIgnored private var manualRebuildTask: Task<Void, Never>?
    @ObservationIgnored private let credentialStore: APICredentialStore
    @ObservationIgnored private let preferences: PreferencesService
    @ObservationIgnored private var persistedToken: String
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var isPreparingForUpdate = false

    init() {
        let preferences = PreferencesService()
        let credentialStore = APICredentialStore()
        self.preferences = preferences
        self.credentialStore = credentialStore
        let storedToken = try? credentialStore.loadToken()
        let legacyToken = storedToken == nil
            ? try? LegacyKeychainStore.value(for: .token)
            : nil
        let initialToken = storedToken ?? legacyToken ?? ""
        let preferredUsername = preferences.firstAPIUsername
        let initialUsername = preferredUsername.isEmpty
            ? (try? LegacyKeychainStore.value(for: .username)) ?? ""
            : preferredUsername
        username = initialUsername
        token = initialToken
        persistedToken = initialToken
        eventCode = preferences.rememberLastEvent ? preferences.lastEventCode : ""
        selectedSeason = preferences.selectedSeason
        sortField = preferences.rankingSortField
        sortDirection = preferences.sortDirection
        rememberLastEvent = preferences.rememberLastEvent
        oprChartLayout = preferences.oprChartLayout

        if preferredUsername.isEmpty && !initialUsername.isEmpty {
            preferences.firstAPIUsername = initialUsername
        }
        if storedToken == nil, let legacyToken, !legacyToken.isEmpty {
            try? credentialStore.saveToken(legacyToken)
        }

        do {
            storedTagGroups = try tagStore.load()
        } catch {
            settingsMessage = "Saved team tags could not be loaded: \(error.localizedDescription)"
        }

        do {
            let loaded = try manualEventStore.loadAll()
            manualEvents = loaded.events
            if !loaded.failures.isEmpty {
                manualEventError = "Some manual events could not be read: \(loaded.failures.joined(separator: ", "))"
            }
        } catch {
            manualEventError = "Manual events could not be loaded: \(error.localizedDescription)"
        }
        if let id = preferences.openManualEventID, manualEvents.contains(where: { $0.id == id }) {
            dataSource = .manual(id)
            rebuildManualEventData()
        }
    }

    var isReady: Bool {
        if case .ready = launchState { return true }
        return false
    }

    var isManualSourceActive: Bool {
        if case .manual = dataSource { return true }
        return false
    }

    /// Manual events work without credentials or the Python helper.
    var canShowDashboard: Bool {
        isReady || isManualSourceActive
    }

    var activeManualEvent: ManualEvent? {
        guard case .manual(let id) = dataSource else { return nil }
        return manualEvents.first { $0.id == id }
    }

    var hasCompleteCredentials: Bool {
        !normalizedUsername.isEmpty && !normalizedToken.isEmpty
    }

    var availableSortFields: [RankingSortField] {
        currentEvent?.mode == .preview
            ? RankingSortField.previewFields
            : RankingSortField.liveFields
    }

    /// Applies a column-header click: a new column sorts in its natural direction,
    /// the active column flips direction.
    func sortByColumn(_ field: RankingSortField) {
        let next = field.headerSort(currentField: sortField, currentDirection: sortDirection)
        if sortDirection != next.direction {
            sortDirection = next.direction
        }
        if sortField != next.field {
            sortField = next.field
        }
    }

    var availableSeasons: [FTCSeason] {
        FTCSeason.supported
    }

    var selectedSeasonOption: FTCSeason {
        FTCSeason.option(for: selectedSeason)
    }

    func startIfNeeded() {
        guard launchState == .idle else { return }
        startBackend()
    }

    func restartBackend() {
        startBackend()
    }

    func prepareForUpdate() async throws {
        isPreparingForUpdate = true
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
        do {
            try await backendService.stopForUpdate()
        } catch {
            isPreparingForUpdate = false
            throw error
        }
    }

    func refreshEvent() {
        guard !isManualSourceActive else { return }
        loadEvent()
    }

    func focusEventCode() {
        guard isReady else { return }
        focusToken += 1
    }

    func loadEvent() {
        guard !isPreparingForUpdate else { return }
        guard case .ready(let context) = launchState else { return }
        let normalized = eventCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            eventLoadState = .failed("Enter an FTC event code.")
            return
        }

        if isManualSourceActive {
            leaveManualEvent()
        }
        eventCode = normalized
        eventLoadState = .loading(normalized)
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let season = selectedSeason

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await eventService.load(
                    eventCode: normalized,
                    season: season,
                    context: context
                )
                guard !Task.isCancelled, generation == loadGeneration else { return }
                currentEvent = data
                lastOnlineEvent = data
                eventCode = data.eventCode
                if rememberLastEvent {
                    preferences.lastEventCode = data.eventCode
                }
                if !availableSortFields.contains(sortField) {
                    sortField = data.mode == .preview ? .seasonOPR : .nonPenaltyOPR
                    sortDirection = .descending
                } else {
                    recomputeRankedStandings()
                }
                eventLoadState = .loaded
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, generation == loadGeneration else { return }
                currentEvent = nil
                lastOnlineEvent = nil
                rankedStandings = []
                eventLoadState = .failed(error.localizedDescription)
            }
        }
    }

    func saveSettings() {
        saveCredentialsAndStart()
    }

    func saveCredentialsAndStart() {
        guard hasCompleteCredentials else {
            settingsMessage = "Enter both your FIRST API username and token."
            launchState = .credentialsRequired
            return
        }

        do {
            username = normalizedUsername
            token = normalizedToken
            if token != persistedToken {
                try credentialStore.saveToken(token)
                persistedToken = token
            }
            preferences.firstAPIUsername = username
            settingsMessage = "Credentials saved. Starting the local data service…"
            startBackend()
        } catch {
            settingsMessage = "Could not save credentials: \(error.localizedDescription)"
            launchState = .credentialsRequired
        }
    }

    func clearEventCache() {
        loadTask?.cancel()
        backendService.stop()
        do {
            try ApplicationDirectories.clearCache()
            lastOnlineEvent = nil
            if !isManualSourceActive {
                currentEvent = nil
                rankedStandings = []
                eventLoadState = .empty
            }
            settingsMessage = "Cached event data was removed."
            startBackend()
        } catch {
            settingsMessage = "Could not clear cached event data: \(error.localizedDescription)"
            startBackend()
        }
    }

    func tags(eventCode: String, teamNumber: Int) -> [TeamTag] {
        storedTagGroups.first {
            $0.eventCode == eventCode && $0.teamNumber == teamNumber
        }?.tags ?? []
    }

    func existingTags(eventCode: String, excludingTeam teamNumber: Int) -> [TeamTag] {
        var seen = Set<String>()
        return storedTagGroups
            .filter { $0.eventCode == eventCode && $0.teamNumber != teamNumber }
            .flatMap(\.tags)
            .filter { seen.insert("\($0.text.lowercased())|\($0.color.rawValue)").inserted }
            .sorted { $0.text.localizedStandardCompare($1.text) == .orderedAscending }
    }

    func addTag(eventCode: String, teamNumber: Int, text: String, color: TagColor) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        addTag(
            eventCode: eventCode,
            teamNumber: teamNumber,
            tag: TeamTag(text: normalized, color: color)
        )
    }

    func reuseTag(eventCode: String, teamNumber: Int, tag: TeamTag) {
        addTag(
            eventCode: eventCode,
            teamNumber: teamNumber,
            tag: TeamTag(text: tag.text, color: tag.color)
        )
    }

    func removeTag(eventCode: String, teamNumber: Int, tagID: UUID) {
        guard let index = storedTagGroups.firstIndex(where: {
            $0.eventCode == eventCode && $0.teamNumber == teamNumber
        }) else { return }
        storedTagGroups[index].tags.removeAll { $0.id == tagID }
        if storedTagGroups[index].tags.isEmpty {
            storedTagGroups.remove(at: index)
        }
        persistTags()
    }

    func matches(for teamNumber: Int) -> [MatchRecord] {
        currentEvent?.matchesByTeam[teamNumber] ?? []
    }

    // MARK: Manual events

    func presentNewManualEvent() {
        isPresentingNewManualEvent = true
    }

    /// Opens the most recently edited manual event, or offers to create the first one.
    func beginManualEntry() {
        if let latest = manualEvents.max(by: { $0.updatedAt < $1.updatedAt }) {
            openManualEvent(id: latest.id)
        } else {
            presentNewManualEvent()
        }
    }

    func createManualEvent(name: String, season: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = ManualEvent(name: trimmed.isEmpty ? "Untitled Event" : trimmed, season: season)
        do {
            try manualEventStore.save(event)
            manualEvents.append(event)
            openManualEvent(id: event.id)
        } catch {
            manualEventError = "The manual event could not be saved: \(error.localizedDescription)"
        }
    }

    func openManualEvent(id: UUID) {
        guard manualEvents.contains(where: { $0.id == id }) else { return }
        if !isManualSourceActive {
            lastOnlineEvent = currentEvent
        }
        // Discard any FIRST Events load still in flight.
        loadTask?.cancel()
        loadGeneration += 1
        dataSource = .manual(id)
        preferences.openManualEventID = id
        rebuildManualEventData()
    }

    /// Returns to FIRST Events, restoring the last online event without refetching it.
    func showOnlineEvents() {
        guard isManualSourceActive else { return }
        leaveManualEvent()
        eventLoadState = currentEvent == nil ? .empty : .loaded
    }

    /// Saves an edited manual event right away and refreshes rankings shortly after,
    /// so typing stays responsive while OPR is recalculated.
    func updateManualEvent(_ event: ManualEvent) {
        guard let index = manualEvents.firstIndex(where: { $0.id == event.id }),
              manualEvents[index] != event else { return }
        var updated = event
        updated.updatedAt = Date()
        manualEvents[index] = updated
        do {
            try manualEventStore.save(updated)
        } catch {
            manualEventError = "Changes to \(updated.name) could not be saved: \(error.localizedDescription)"
        }
        guard activeManualEvent?.id == event.id else { return }
        manualRebuildTask?.cancel()
        manualRebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.rebuildManualEventData()
        }
    }

    func renameManualEvent(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var event = manualEvents.first(where: { $0.id == id }) else { return }
        event.name = trimmed
        updateManualEvent(event)
    }

    func deleteManualEvent(id: UUID) {
        guard let event = manualEvents.first(where: { $0.id == id }) else { return }
        do {
            try manualEventStore.delete(id: id)
        } catch {
            manualEventError = "\(event.name) could not be deleted: \(error.localizedDescription)"
            return
        }
        if activeManualEvent?.id == id {
            showOnlineEvents()
        }
        manualEvents.removeAll { $0.id == id }
        let tagCount = storedTagGroups.count
        storedTagGroups.removeAll { $0.eventCode == event.eventCode }
        if storedTagGroups.count != tagCount {
            persistTags()
        }
    }

    /// Adds matches from a CSV to a manual event, or replaces its matches, and reports
    /// which rows were skipped.
    func importManualMatches(
        from url: URL,
        into id: UUID,
        replacing: Bool
    ) throws -> ManualEventCSV.ImportResult {
        guard var event = manualEvents.first(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let result = try ManualEventCSV.importMatches(
            from: data,
            season: event.season,
            existing: replacing ? [] : event.matches
        )
        event.matches = replacing ? result.matches : event.matches + result.matches
        updateManualEvent(event)
        return result
    }

    private func leaveManualEvent() {
        manualRebuildTask?.cancel()
        dataSource = .online
        preferences.openManualEventID = nil
        currentEvent = lastOnlineEvent
        recomputeRankedStandings()
    }

    private func rebuildManualEventData() {
        guard let event = activeManualEvent else { return }
        currentEvent = ManualEventBuilder.eventData(for: event)
        eventLoadState = .loaded
        if !availableSortFields.contains(sortField) {
            sortField = .nonPenaltyOPR
            sortDirection = .descending
        } else {
            recomputeRankedStandings()
        }
    }

    private func addTag(eventCode: String, teamNumber: Int, tag: TeamTag) {
        if let index = storedTagGroups.firstIndex(where: {
            $0.eventCode == eventCode && $0.teamNumber == teamNumber
        }) {
            let duplicate = storedTagGroups[index].tags.contains {
                $0.text.caseInsensitiveCompare(tag.text) == .orderedSame && $0.color == tag.color
            }
            guard !duplicate else { return }
            storedTagGroups[index].tags.append(tag)
        } else {
            storedTagGroups.append(StoredTeamTags(
                eventCode: eventCode,
                teamNumber: teamNumber,
                tags: [tag]
            ))
        }
        storedTagGroups.sort {
            ($0.eventCode, $0.teamNumber) < ($1.eventCode, $1.teamNumber)
        }
        persistTags()
    }

    private func persistTags() {
        do {
            try tagStore.save(storedTagGroups)
        } catch {
            settingsMessage = "Team tags could not be saved: \(error.localizedDescription)"
        }
    }

    private func startBackend() {
        guard !isPreparingForUpdate else { return }
        guard hasCompleteCredentials else {
            backendService.stop()
            settingsMessage = nil
            launchState = .credentialsRequired
            return
        }

        launchState = .starting
        backendService.start(
            username: normalizedUsername,
            token: normalizedToken
        ) { [weak self] result in
            guard let self, !self.isPreparingForUpdate else { return }
            switch result {
            case .success(let context):
                self.launchState = .ready(context)
                self.settingsMessage = "Credentials saved. The local data service is ready."
            case .failure(let error):
                if let backendError = error as? BackendServiceError,
                   case .pythonNotFound = backendError {
                    self.launchState = .pythonRequired
                } else {
                    self.launchState = .failed(error.localizedDescription)
                }
                self.settingsMessage = error.localizedDescription
            }
        }
    }

    private func handleSeasonChange() {
        loadTask?.cancel()
        loadGeneration += 1
        lastOnlineEvent = nil
        // The season picker belongs to FIRST Events; a manual event keeps its own season.
        guard !isManualSourceActive else { return }
        currentEvent = nil
        rankedStandings = []
        eventLoadState = .empty

        guard isReady,
              !eventCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        loadEvent()
    }

    private func recomputeRankedStandings() {
        guard let event = currentEvent else {
            rankedStandings = []
            return
        }
        let sorted = event.standings.sorted(by: standingComesBefore)
        rankedStandings = sorted.enumerated().map { index, standing in
            RankedStanding(order: index + 1, team: standing)
        }
    }

    private func standingComesBefore(_ lhs: TeamStanding, _ rhs: TeamStanding) -> Bool {
        let result: Int
        switch sortField {
        case .storedRank:
            result = compare(lhs.storedRank, rhs.storedRank)
        case .teamNumber:
            result = compare(lhs.teamNumber, rhs.teamNumber)
        case .totalOPR:
            result = compareOptional(lhs.totalOPR, rhs.totalOPR)
        case .oprc:
            result = compareOptional(
                currentEvent?.oprcAnalysis.teamMetrics[lhs.teamNumber]?.oprc,
                currentEvent?.oprcAnalysis.teamMetrics[rhs.teamNumber]?.oprc
            )
        case .nonPenaltyOPR:
            result = compareOptional(lhs.nonPenaltyOPR, rhs.nonPenaltyOPR)
        case .autoOPR:
            result = compareOptional(lhs.autoOPR, rhs.autoOPR)
        case .teleopOPR:
            result = compareOptional(lhs.teleopOPR, rhs.teleopOPR)
        case .endgameOPR:
            result = compareOptional(lhs.endgameOPR, rhs.endgameOPR)
        case .teamName:
            result = compare(lhs.teamName.localizedLowercase, rhs.teamName.localizedLowercase)
        case .seasonOPR:
            result = compareOptional(lhs.seasonOPR, rhs.seasonOPR)
        case .rookieYear:
            result = compareOptional(lhs.rookieYear, rhs.rookieYear)
        case .record:
            result = compareOptional(playedRecord(for: lhs), playedRecord(for: rhs))
        case .played:
            // Teams without a scored qualification match have played zero, as the column shows.
            result = compare(
                currentEvent?.teamRecords[lhs.teamNumber]?.played ?? 0,
                currentEvent?.teamRecords[rhs.teamNumber]?.played ?? 0
            )
        }

        if result == 0 { return lhs.teamNumber < rhs.teamNumber }
        if result == 2 { return false }
        if result == -2 { return true }
        return sortDirection == .ascending ? result < 0 : result > 0
    }

    private func playedRecord(for standing: TeamStanding) -> TeamEventRecord? {
        guard let record = currentEvent?.teamRecords[standing.teamNumber],
              record.played > 0 else {
            return nil
        }
        return record
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> Int {
        if lhs < rhs { return -1 }
        if lhs > rhs { return 1 }
        return 0
    }

    private func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> Int {
        switch (lhs, rhs) {
        case (.none, .none): 0
        case (.none, .some): 2
        case (.some, .none): -2
        case (.some(let lhs), .some(let rhs)): compare(lhs, rhs)
        }
    }

    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
