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

    private(set) var currentEvent: EventData?
    private(set) var rankedStandings: [RankedStanding] = []
    private(set) var storedTagGroups: [StoredTeamTags] = []
    private(set) var focusToken = 0

    @ObservationIgnored private let backendService = BackendService()
    @ObservationIgnored private let eventService = EventService()
    @ObservationIgnored private let tagStore = TagStore()
    @ObservationIgnored private let credentialStore: APICredentialStore
    @ObservationIgnored private let preferences: PreferencesService
    @ObservationIgnored private var persistedToken: String
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0

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
    }

    var isReady: Bool {
        if case .ready = launchState { return true }
        return false
    }

    var hasCompleteCredentials: Bool {
        !normalizedUsername.isEmpty && !normalizedToken.isEmpty
    }

    var availableSortFields: [RankingSortField] {
        currentEvent?.mode == .preview
            ? RankingSortField.previewFields
            : RankingSortField.liveFields
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

    func refreshEvent() {
        loadEvent()
    }

    func focusEventCode() {
        guard isReady else { return }
        focusToken += 1
    }

    func loadEvent() {
        guard case .ready(let context) = launchState else { return }
        let normalized = eventCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            eventLoadState = .failed("Enter an FTC event code.")
            return
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
                eventCode = data.eventCode
                if rememberLastEvent {
                    preferences.lastEventCode = data.eventCode
                }
                if !availableSortFields.contains(sortField) {
                    sortField = data.mode == .preview ? .highestOPR : .nonPenaltyOPR
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
            currentEvent = nil
            rankedStandings = []
            eventLoadState = .empty
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
            guard let self else { return }
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
        case .highestOPR:
            result = compareOptional(lhs.highestOPR, rhs.highestOPR)
        case .bestSeason:
            result = compareOptional(lhs.bestSeason, rhs.bestSeason)
        case .rookieYear:
            result = compareOptional(lhs.rookieYear, rhs.rookieYear)
        }

        if result == 0 { return lhs.teamNumber < rhs.teamNumber }
        if result == 2 { return false }
        if result == -2 { return true }
        return sortDirection == .ascending ? result < 0 : result > 0
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
