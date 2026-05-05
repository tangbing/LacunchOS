import Foundation

struct AppRecord: Codable, Hashable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable {
        case system
        case local
        case user
        case custom
    }

    let id: String
    let bundleIdentifier: String?
    let bundleName: String
    let displayName: String
    let path: String
    let source: Source
    var alias: String?
    var isHidden: Bool
    var lastOpenedAt: Date?

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var searchableNames: [String] {
        [displayName, bundleName, alias]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
