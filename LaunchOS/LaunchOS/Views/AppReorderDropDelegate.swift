import SwiftUI

struct AppReorderDropDelegate: DropDelegate {
    let targetItem: LauncherItem
    let model: LauncherModel

    func validateDrop(info: DropInfo) -> Bool {
        model.canReorderApps && model.draggingAppID != nil
    }

    func dropEntered(info: DropInfo) {
        updateDropState(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropState(info: info)
        return DropProposal(operation: model.canReorderApps ? .move : .cancel)
    }

    func dropExited(info: DropInfo) {
        if model.folderDropTargetID == targetItem.id {
            model.clearFolderDropTarget()
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard model.canReorderApps else {
            model.finishDragging(saveChanges: false)
            return false
        }

        if isFolderDrop(info: info) {
            withAnimation(.snappy(duration: 0.18)) {
                model.groupDraggingApp(with: targetItem)
            }
        }

        model.finishDragging()
        return true
    }

    private func updateDropState(info: DropInfo) {
        guard model.canReorderApps else {
            return
        }

        if isFolderDrop(info: info) {
            model.previewFolderDrop(on: targetItem.id)
        } else {
            withAnimation(.snappy(duration: 0.16)) {
                model.moveDraggingApp(over: targetItem.id)
            }
        }
    }

    private func isFolderDrop(info: DropInfo) -> Bool {
        guard model.canGroupDraggingApp(with: targetItem) else {
            return false
        }

        let location = info.location
        return (18...106).contains(location.x) && (0...96).contains(location.y)
    }
}

struct AppGridDropDelegate: DropDelegate {
    let model: LauncherModel

    func validateDrop(info: DropInfo) -> Bool {
        model.canReorderApps && model.draggingAppID != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: model.canReorderApps ? .move : .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard model.canReorderApps else {
            model.finishDragging(saveChanges: false)
            return false
        }

        model.finishDragging()
        return true
    }
}
