import Foundation

struct PreferencesService {
    private enum Key {
        static let firstAPIUsername = "firstAPIUsername"
        static let lastEventCode = "lastEventCode"
        static let selectedSeason = "selectedSeason"
        static let rankingSortField = "rankingSortField"
        static let sortDirection = "sortDirection"
        static let rememberLastEvent = "rememberLastEvent"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.selectedSeason: FTCSeason.defaultStartYear,
            Key.rankingSortField: RankingSortField.nonPenaltyOPR.rawValue,
            Key.sortDirection: SortDirection.descending.rawValue,
            Key.rememberLastEvent: true,
        ])
    }

    var firstAPIUsername: String {
        get { defaults.string(forKey: Key.firstAPIUsername) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.firstAPIUsername) }
    }

    var lastEventCode: String {
        get { defaults.string(forKey: Key.lastEventCode) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.lastEventCode) }
    }

    var selectedSeason: Int {
        get {
            let storedYear = defaults.integer(forKey: Key.selectedSeason)
            return FTCSeason.option(for: storedYear).startYear
        }
        nonmutating set { defaults.set(newValue, forKey: Key.selectedSeason) }
    }

    var rankingSortField: RankingSortField {
        get {
            let rawValue = defaults.string(forKey: Key.rankingSortField) ?? ""
            return RankingSortField(rawValue: rawValue) ?? .nonPenaltyOPR
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.rankingSortField) }
    }

    var sortDirection: SortDirection {
        get {
            let rawValue = defaults.string(forKey: Key.sortDirection) ?? ""
            return SortDirection(rawValue: rawValue) ?? .descending
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.sortDirection) }
    }

    var rememberLastEvent: Bool {
        get { defaults.bool(forKey: Key.rememberLastEvent) }
        nonmutating set { defaults.set(newValue, forKey: Key.rememberLastEvent) }
    }
}
