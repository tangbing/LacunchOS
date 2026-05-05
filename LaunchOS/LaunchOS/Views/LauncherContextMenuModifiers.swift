import SwiftUI

private struct AppContextMenuModifier: ViewModifier {
    let app: AppRecord
    let model: LauncherModel

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                model.launch(app)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }

            Button {
                model.showInFinder(app)
            } label: {
                Label("Show in Finder", systemImage: "finder")
            }

            if model.folderMoveTargets(for: app.id).isEmpty {
                Button {} label: {
                    Label("Move to Folder", systemImage: "folder")
                }
                .disabled(true)
            } else {
                Menu {
                    ForEach(model.folderMoveTargets(for: app.id)) { folder in
                        Button(folder.name) {
                            model.moveApp(app.id, toFolder: folder.id)
                        }
                    }
                } label: {
                    Label("Move to Folder", systemImage: "folder")
                }
            }

            Divider()

            Button {
                model.requestAppAlias(app.id)
            } label: {
                Label("Rename / Set Alias", systemImage: "pencil")
            }

            Button(role: .destructive) {
                model.hideApp(app.id)
            } label: {
                Label("Hide App", systemImage: "eye.slash")
            }
        }
    }
}

private struct FolderContextMenuModifier: ViewModifier {
    let folder: LauncherFolder
    let model: LauncherModel

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                model.openFolder(folder.id)
            } label: {
                Label("Open", systemImage: "folder")
            }

            Button {
                model.requestRenameFolder(folder.id)
            } label: {
                Label("Rename Folder", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                model.requestDissolveFolder(folder.id)
            } label: {
                Label("Dissolve Folder", systemImage: "square.grid.3x3")
            }
        }
    }
}

extension View {
    func launcherAppContextMenu(for app: AppRecord, model: LauncherModel) -> some View {
        modifier(AppContextMenuModifier(app: app, model: model))
    }

    func launcherFolderContextMenu(for folder: LauncherFolder, model: LauncherModel) -> some View {
        modifier(FolderContextMenuModifier(folder: folder, model: model))
    }
}
