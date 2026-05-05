import Foundation

struct SearchService {
    func results(for query: String, in apps: [AppRecord]) -> [AppRecord] {
        let normalizedQuery = normalize(query)

        guard !normalizedQuery.isEmpty else {
            return apps
        }

        return apps
            .compactMap { app -> (app: AppRecord, score: Int)? in
                let score = score(app, query: normalizedQuery)
                return score > 0 ? (app, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.app.displayName.localizedCaseInsensitiveCompare(rhs.app.displayName) == .orderedAscending
                }

                return lhs.score > rhs.score
            }
            .map(\.app)
    }

    private func score(_ app: AppRecord, query: String) -> Int {
        app.searchableNames.reduce(0) { bestScore, name in
            max(bestScore, score(name, query: query))
        }
    }

    private func score(_ name: String, query: String) -> Int {
        let normalizedName = normalize(name)

        if normalizedName == query {
            return 100
        }

        if normalizedName.hasPrefix(query) {
            return 80
        }

        if initials(for: name).hasPrefix(query) {
            return 70
        }

        if normalizedName.contains(query) {
            return 50
        }

        if abbreviation(for: name).hasPrefix(query) {
            return 40
        }

        return 0
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func initials(for value: String) -> String {
        value
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap(\.first)
            .map { String($0).lowercased() }
            .joined()
    }

    private func abbreviation(for value: String) -> String {
        value
            .filter { $0.isUppercase || $0.isNumber }
            .map { String($0).lowercased() }
            .joined()
    }
}
