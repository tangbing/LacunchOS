import Foundation

struct AppScanner {
    nonisolated func scanDefaultApplications() async throws -> [AppRecord] {
        try await scanApplications(additionalDirectoryPaths: [])
    }

    nonisolated func scanApplications(additionalDirectoryPaths: [String]) async throws -> [AppRecord] {
        try await Task.detached(priority: .userInitiated) {
            try Self.scanApplicationDirectories(additionalDirectoryPaths: additionalDirectoryPaths)
        }.value
    }

    nonisolated private static func scanApplicationDirectories(additionalDirectoryPaths: [String]) throws -> [AppRecord] {
        let fileManager = FileManager.default
        var directories: [(URL, AppRecord.Source)] = [
            (URL(fileURLWithPath: "/System/Applications"), .system),
            (URL(fileURLWithPath: "/Applications"), .local),
            (fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"), .user)
        ]
        let customDirectories = LayoutSettings.normalizedDirectoryPaths(additionalDirectoryPaths)
            .map { (URL(fileURLWithPath: $0, isDirectory: true), AppRecord.Source.custom) }

        directories.append(contentsOf: customDirectories)

        var records: [AppRecord] = []
        var scannedDirectoryPaths: Set<String> = []

        for (directory, source) in directories where directoryExists(directory, fileManager: fileManager) {
            guard scannedDirectoryPaths.insert(directory.standardizedFileURL.path).inserted else {
                continue
            }

            records.append(contentsOf: scan(directory: directory, source: source, fileManager: fileManager))
        }

        return deduplicated(records)
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    nonisolated private static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    nonisolated private static func scan(
        directory: URL,
        source: AppRecord.Source,
        fileManager: FileManager
    ) -> [AppRecord] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isAliasFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var records: [AppRecord] = []

        for case let url as URL in enumerator {
            guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                continue
            }

            if let record = makeRecord(from: url, source: source) {
                records.append(record)
            }

            enumerator.skipDescendants()
        }

        return records
    }

    nonisolated private static func makeRecord(from url: URL, source: AppRecord.Source) -> AppRecord? {
        let standardizedURL = url.standardizedFileURL
        let bundle = Bundle(url: standardizedURL)
        let bundleIdentifier = bundle?.bundleIdentifier
        let bundleName = value(for: "CFBundleName", in: bundle)
            ?? standardizedURL.deletingPathExtension().lastPathComponent
        let displayName = value(for: "CFBundleDisplayName", in: bundle)
            ?? bundleName

        return AppRecord(
            id: bundleIdentifier ?? standardizedURL.path,
            bundleIdentifier: bundleIdentifier,
            bundleName: bundleName,
            displayName: displayName,
            path: standardizedURL.path,
            source: source,
            alias: nil,
            isHidden: false,
            lastOpenedAt: nil
        )
    }

    nonisolated private static func value(for key: String, in bundle: Bundle?) -> String? {
        bundle?.object(forInfoDictionaryKey: key) as? String
    }

    nonisolated private static func deduplicated(_ records: [AppRecord]) -> [AppRecord] {
        var seenPaths = Set<String>()
        var seenBundleIdentifiers = Set<String>()
        var result: [AppRecord] = []

        for record in records {
            guard seenPaths.insert(record.path).inserted else {
                continue
            }

            if let bundleIdentifier = record.bundleIdentifier {
                guard seenBundleIdentifiers.insert(bundleIdentifier).inserted else {
                    continue
                }
            }

            result.append(record)
        }

        return result
    }
}
