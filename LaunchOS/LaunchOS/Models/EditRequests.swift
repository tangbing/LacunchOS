import Foundation

struct FolderRenameRequest: Identifiable, Hashable, Sendable {
    let id: LauncherFolder.ID
    let currentName: String
}

struct FolderDissolveRequest: Identifiable, Hashable, Sendable {
    let id: LauncherFolder.ID
    let name: String
    let appCount: Int
}

struct AppAliasRequest: Identifiable, Hashable, Sendable {
    let id: AppRecord.ID
    let displayName: String
    let currentAlias: String
}
