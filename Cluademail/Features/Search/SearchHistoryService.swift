import Foundation
import os.log

/// Represents a saved search query with filters.
struct SearchHistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let query: String
    let filters: SearchFilters
    let date: Date

    init(query: String, filters: SearchFilters = SearchFilters()) {
        self.id = UUID()
        self.query = query
        self.filters = filters
        self.date = Date()
    }
}

/// Service for persisting recent searches to UserDefaults.
@MainActor
final class SearchHistoryService {

    // MARK: - Constants

    private let maxHistoryItems = 20
    private let userDefaultsKey = "searchHistory"

    // MARK: - Singleton

    static let shared = SearchHistoryService()

    private init() {}

    // MARK: - Public Interface

    /// Returns all saved search history items.
    func getHistory() -> [SearchHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([SearchHistoryItem].self, from: data)
        } catch {
            Logger.ui.error("Failed to decode search history: \(error.localizedDescription)")
            return []
        }
    }

    /// Adds a search to history, removing duplicates and limiting to max items.
    /// - Parameters:
    ///   - query: The search query text
    ///   - filters: The search filters applied
    func addSearch(_ query: String, filters: SearchFilters = SearchFilters()) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        var history = getHistory()

        // Remove existing duplicate (same query)
        history.removeAll { $0.query.lowercased() == query.lowercased() }

        // Insert at front
        let item = SearchHistoryItem(query: query, filters: filters)
        history.insert(item, at: 0)

        // Trim to max items
        if history.count > maxHistoryItems {
            history = Array(history.prefix(maxHistoryItems))
        }

        saveHistory(history)
        Logger.ui.debug("Added search to history: \(query)")
    }

    /// Deletes a specific search from history.
    /// - Parameter id: The ID of the search to delete
    func deleteSearch(id: UUID) {
        var history = getHistory()
        history.removeAll { $0.id == id }
        saveHistory(history)
        Logger.ui.debug("Deleted search from history: \(id)")
    }

    /// Clears all search history.
    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        Logger.ui.debug("Cleared search history")
    }

    /// Filters history by query text (case-insensitive).
    /// - Parameter query: Text to filter by
    /// - Returns: Matching history items
    func filterHistory(by query: String) -> [SearchHistoryItem] {
        guard !query.isEmpty else { return getHistory() }
        let lowercasedQuery = query.lowercased()
        return getHistory().filter { $0.query.lowercased().contains(lowercasedQuery) }
    }

    // MARK: - Private

    private func saveHistory(_ history: [SearchHistoryItem]) {
        do {
            let data = try JSONEncoder().encode(history)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            Logger.ui.error("Failed to save search history: \(error.localizedDescription)")
        }
    }
}
