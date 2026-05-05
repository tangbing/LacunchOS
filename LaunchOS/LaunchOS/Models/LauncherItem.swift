import Foundation

struct LauncherItem: Hashable, Identifiable, Sendable {
    enum Kind: Hashable, Sendable {
        case app
        case folder
    }

    let id: String
    let kind: Kind
    let app: AppRecord?
    let folder: LauncherFolder?
    let folderApps: [AppRecord]

    var title: String {
        switch kind {
        case .app:
            app?.alias ?? app?.displayName ?? ""
        case .folder:
            folder?.name ?? "Folder"
        }
    }

    static func app(_ app: AppRecord) -> LauncherItem {
        LauncherItem(id: app.id, kind: .app, app: app, folder: nil, folderApps: [])
    }

    static func folder(_ folder: LauncherFolder, apps: [AppRecord]) -> LauncherItem {
        LauncherItem(id: folder.id, kind: .folder, app: nil, folder: folder, folderApps: apps)
    }
}
