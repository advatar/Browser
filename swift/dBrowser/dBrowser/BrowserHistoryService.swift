//
//  BrowserHistoryService.swift
//  dBrowser
//
//  Owns the browser's smart-history domain extracted from BrowserViewModel: history recording,
//  smart-history summarization and exclusion config, address-bar autocomplete ranking, and
//  persistence. The view model continues to own the observable `history` array and delegates the
//  domain logic here, shrinking its responsibilities.
//

import Foundation

final class BrowserHistoryService {
    private let store: SmartHistoryStore
    private(set) var excludedDomains: Set<String>

    /// History loaded from persistence at construction, for the view model to seed its state.
    let initialHistory: [BrowserHistoryEntry]

    init(store: SmartHistoryStore) {
        self.store = store
        let payload = store.load()
        self.excludedDomains = Set(payload.excludedDomains)
        self.initialHistory = payload.history
    }

    // MARK: - Recording

    func recording(title: String, urlString: String, into history: [BrowserHistoryEntry]) -> [BrowserHistoryEntry] {
        guard urlString != BrowserURLResolver.homeURLString else { return history }
        var updated = history
        let previousEntry = updated.first { $0.urlString == urlString }
        updated.removeAll { $0.urlString == urlString }
        let isIndexed = isIndexable(urlString)
        let summary = isIndexed
            ? previousEntry?.summary ?? SmartHistoryIndexer.summary(title: title, urlString: urlString)
            : nil
        updated.insert(
            BrowserHistoryEntry(
                title: title,
                urlString: urlString,
                visitedAt: Date(),
                summary: summary,
                isSmartHistoryIndexed: isIndexed
            ),
            at: 0
        )
        if updated.count > 100 {
            updated.removeLast(updated.count - 100)
        }
        persist(updated)
        return updated
    }

    func updatingSummary(from snapshot: PageSnapshot, in history: [BrowserHistoryEntry]) -> [BrowserHistoryEntry] {
        guard isIndexable(snapshot.urlString) else { return history }
        guard let index = history.firstIndex(where: { $0.urlString == snapshot.urlString }) else { return history }
        var updated = history
        updated[index].summary = SmartHistoryIndexer.summary(
            title: updated[index].title,
            urlString: updated[index].urlString,
            snapshot: snapshot
        )
        updated[index].isSmartHistoryIndexed = true
        persist(updated)
        return updated
    }

    func settingIndexing(enabled: Bool, forDomain domain: String, in history: [BrowserHistoryEntry]) -> [BrowserHistoryEntry] {
        let normalizedDomain = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDomain.isEmpty else { return history }
        var updated = history
        if enabled {
            excludedDomains.remove(normalizedDomain)
        } else {
            excludedDomains.insert(normalizedDomain)
            for index in updated.indices where URL(string: updated[index].urlString)?.host?.lowercased() == normalizedDomain {
                updated[index].summary = nil
                updated[index].isSmartHistoryIndexed = false
            }
        }
        persist(updated)
        return updated
    }

    func clearingSummaries(in history: [BrowserHistoryEntry]) -> [BrowserHistoryEntry] {
        var updated = history
        for index in updated.indices {
            updated[index].summary = nil
            updated[index].isSmartHistoryIndexed = false
        }
        persist(updated)
        return updated
    }

    func deleting(id: UUID, from history: [BrowserHistoryEntry]) -> [BrowserHistoryEntry] {
        var updated = history
        updated.removeAll { $0.id == id }
        persist(updated)
        return updated
    }

    func isIndexable(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return true }
        return !excludedDomains.contains(host)
    }

    func persist(_ history: [BrowserHistoryEntry]) {
        store.save(
            SmartHistoryStorePayload(
                history: history,
                excludedDomains: Array(excludedDomains).sorted()
            )
        )
    }

    // MARK: - Recall

    func smartHistoryRecall(_ query: String, in history: [BrowserHistoryEntry], limit: Int) -> [SmartHistoryRecallResult] {
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !terms.isEmpty else { return [] }

        return history.compactMap { entry -> SmartHistoryRecallResult? in
            guard entry.isSmartHistoryIndexed else { return nil }
            let searchable = [
                entry.title,
                entry.urlString,
                entry.summary ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            guard terms.allSatisfy({ searchable.contains($0) }) else { return nil }

            var score = 0
            for term in terms {
                if entry.title.lowercased().contains(term) { score += 4 }
                if entry.urlString.lowercased().contains(term) { score += 3 }
                if entry.summary?.lowercased().contains(term) == true { score += 5 }
            }
            return SmartHistoryRecallResult(entry: entry, score: score, matchedText: entry.summary ?? entry.title)
        }
        .sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.entry.visitedAt > $1.entry.visitedAt
        }
        .prefix(limit)
        .map { $0 }
    }

    // MARK: - Autocomplete

    func autocompleteSuggestions(matching rawQuery: String, in history: [BrowserHistoryEntry], limit: Int) -> [BrowserAddressSuggestion] {
        let normalizedQuery = normalizedAutocompleteText(rawQuery)
        guard !normalizedQuery.isEmpty else { return [] }

        var seenURLs = Set<String>()
        let rankedSuggestions = history.enumerated().compactMap { index, entry -> (rank: Int, index: Int, suggestion: BrowserAddressSuggestion)? in
            let normalizedURL = normalizedAutocompleteText(entry.urlString)
            guard seenURLs.insert(normalizedURL).inserted else { return nil }
            guard let rank = autocompleteRank(for: entry, query: normalizedQuery) else { return nil }

            return (
                rank,
                index,
                BrowserAddressSuggestion(title: entry.title, urlString: entry.urlString)
            )
        }

        return rankedSuggestions
            .sorted {
                if $0.rank != $1.rank {
                    return $0.rank < $1.rank
                }
                return $0.index < $1.index
            }
            .prefix(limit)
            .map { $0.suggestion }
    }

    private func autocompleteRank(for entry: BrowserHistoryEntry, query: String) -> Int? {
        let normalizedURL = normalizedAutocompleteText(entry.urlString)
        let displayURL = displayAutocompleteText(for: entry.urlString)
        let host = URL(string: entry.urlString)?.host.map(normalizedAutocompleteText) ?? ""
        let title = normalizedAutocompleteText(entry.title)

        guard normalizedURL != query, displayURL != query else {
            return nil
        }

        if normalizedURL.hasPrefix(query) {
            return 0
        }
        if displayURL.hasPrefix(query) {
            return 1
        }
        if host.hasPrefix(query) {
            return 2
        }
        if normalizedURL.contains(query) || displayURL.contains(query) {
            return 3
        }
        if title.contains(query) {
            return 4
        }
        if entry.summary?.lowercased().contains(query) == true {
            return 5
        }
        return nil
    }

    private func normalizedAutocompleteText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func displayAutocompleteText(for urlString: String) -> String {
        var text = normalizedAutocompleteText(urlString)
        for prefix in ["https://www.", "http://www.", "https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }
        return text
    }
}
