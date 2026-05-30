import AppKit
import Observation

struct AppDragPreviewState: Equatable {
    let appID: AppRecord.ID
    var locationInWindow: CGPoint
    var cursorOffsetFromCenter: CGSize
}

private struct DragRestoreState {
    var folders: [LauncherFolder]
    var orderedItemIDs: [LauncherItem.ID]
    var currentPage: Int
    var selectedItemID: LauncherItem.ID?
    var openedFolderID: LauncherFolder.ID?
}

@MainActor
@Observable
final class LauncherModel {
    var apps: [AppRecord] = []
    var folders: [LauncherFolder] = []
    var orderedItemIDs: [LauncherItem.ID] = []
    var searchText = ""
    var isLoading = false
    var errorMessage: String?
    var layoutWarningMessage: String?
    var selectedItemID: LauncherItem.ID?
    var currentPage = 0
    var itemsPerPage = 1
    var columnCount = 1
    var layoutSettings = LayoutSettings()
    var draggingAppID: AppRecord.ID?
    var draggingSourceFolderID: LauncherFolder.ID?
    var dragPreviewState: AppDragPreviewState?
    var folderDropTargetID: LauncherItem.ID?
    var openedFolderID: LauncherFolder.ID?
    var folderRenameRequest: FolderRenameRequest?
    var folderDissolveRequest: FolderDissolveRequest?
    var appAliasRequest: AppAliasRequest?
    var iconRefreshToken = UUID()

    @ObservationIgnored private let scanner: AppScanner
    @ObservationIgnored private let launcher: AppLauncher
    @ObservationIgnored private let searchService: SearchService
    @ObservationIgnored private let layoutStore: LayoutStore
    @ObservationIgnored private var hasLoadedLayout = false
    @ObservationIgnored private var folderDropPreviewTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFolderDropTargetID: LauncherItem.ID?
    @ObservationIgnored private var dragRestoreState: DragRestoreState?

    init() {
        scanner = AppScanner()
        launcher = AppLauncher()
        searchService = SearchService()
        layoutStore = LayoutStore()
    }

    var visibleApps: [AppRecord] {
        searchService.results(for: searchText, in: apps.filter { !$0.isHidden })
    }

    var draggingApp: AppRecord? {
        guard let draggingAppID else {
            return nil
        }

        return apps.first { $0.id == draggingAppID }
    }

    var visibleItems: [LauncherItem] {
        if searchText.isEmpty {
            return topLevelItems()
        }

        return visibleApps.map(LauncherItem.app)
    }

    var pageCount: Int {
        guard !isVerticalBrowsing else {
            return 1
        }

        return max(1, Int(ceil(Double(visibleItems.count) / Double(max(1, itemsPerPage)))))
    }

    var currentPageItems: [LauncherItem] {
        guard !isVerticalBrowsing else {
            return visibleItems
        }

        let safePage = min(currentPage, pageCount - 1)
        let startIndex = safePage * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, visibleItems.count)

        guard startIndex < endIndex else {
            return []
        }

        return Array(visibleItems[startIndex..<endIndex])
    }

    var canReorderApps: Bool {
        searchText.isEmpty && !isLoading && errorMessage == nil
    }

    var isVerticalBrowsing: Bool {
        layoutSettings.browsingMode == .verticalScroll
    }

    var openedFolder: LauncherFolder? {
        guard let openedFolderID else {
            return nil
        }

        return folders.first { $0.id == openedFolderID }
    }

    var openedFolderApps: [AppRecord] {
        guard let openedFolder else {
            return []
        }

        return apps(in: openedFolder)
    }

    var hiddenApps: [AppRecord] {
        apps
            .filter(\.isHidden)
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    func folderMoveTargets(for appID: AppRecord.ID) -> [LauncherFolder] {
        folders.filter { !$0.appIDs.contains(appID) }
    }

    func refreshAppsIfNeeded() async {
        guard apps.isEmpty else {
            return
        }

        await refreshApps()
    }

    func refreshApps() async {
        isLoading = true
        errorMessage = nil

        do {
            let savedLayout = hasLoadedLayout || !apps.isEmpty ? currentLayoutSnapshot() : await loadSavedLayout()
            let scannedApps = try await scanner.scanApplications(
                additionalDirectoryPaths: savedLayout.settings.customApplicationDirectoryPaths
            )
            let appliedLayout = layoutStore.applying(savedLayout, to: scannedApps)

            layoutSettings = settingsByUpdatingGrid(savedLayout.settings)
            apps = appliedLayout.apps
            folders = appliedLayout.folders
            orderedItemIDs = appliedLayout.orderedItemIDs
            hasLoadedLayout = true
            currentPage = savedLayout.settings.remembersLastPage && !isVerticalBrowsing ? savedLayout.currentPage : 0
            currentPage = min(currentPage, pageCount - 1)
            selectedItemID = visibleItems.first?.id
            saveCurrentLayout()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func updateGrid(columns: Int, itemsPerPage: Int) {
        columnCount = max(1, columns)
        self.itemsPerPage = max(1, itemsPerPage)
        currentPage = isVerticalBrowsing ? 0 : min(currentPage, pageCount - 1)

        let newSettings = settingsByUpdatingGrid(layoutSettings)

        guard newSettings != layoutSettings else {
            return
        }

        layoutSettings = newSettings
        saveCurrentLayout()
    }

    func updateItemsPerPage(_ value: Int) {
        itemsPerPage = max(1, value)
        currentPage = min(currentPage, pageCount - 1)
    }

    func updateBrowsingMode(_ browsingMode: LayoutSettings.BrowsingMode) {
        updateLayoutSettings { settings in
            settings.browsingMode = browsingMode
        }
    }

    func updateRemembersLastPage(_ remembersLastPage: Bool) {
        updateLayoutSettings { settings in
            settings.remembersLastPage = remembersLastPage
        }
    }

    func updateCustomGridEnabled(_ isEnabled: Bool) {
        updateLayoutSettings { settings in
            settings.usesCustomGrid = isEnabled
        }
    }

    func updateCustomColumnCount(_ columnCount: Int) {
        updateLayoutSettings { settings in
            settings.customColumnCount = columnCount
        }
    }

    func updateCustomRowCount(_ rowCount: Int) {
        updateLayoutSettings { settings in
            settings.customRowCount = rowCount
        }
    }

    func addCustomApplicationDirectories(_ paths: [String]) {
        let newPaths = LayoutSettings.normalizedDirectoryPaths(paths)

        guard !newPaths.isEmpty else {
            return
        }

        updateLayoutSettings { settings in
            settings.customApplicationDirectoryPaths = LayoutSettings.normalizedDirectoryPaths(
                settings.customApplicationDirectoryPaths + newPaths
            )
        }

        Task {
            await refreshApps()
        }
    }

    func removeCustomApplicationDirectory(_ path: String) {
        let normalizedPath = LayoutSettings.normalizedDirectoryPaths([path]).first ?? path

        updateLayoutSettings { settings in
            settings.customApplicationDirectoryPaths.removeAll { $0 == normalizedPath || $0 == path }
        }

        Task {
            await refreshApps()
        }
    }

    func exportLayoutBackup(to url: URL) async {
        let isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()

        defer {
            if isAccessingSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try await layoutStore.save(currentLayoutSnapshot(), to: url)
            layoutWarningMessage = String(localized: "Backup exported.")
        } catch {
            layoutWarningMessage = String(localized: "Backup could not be exported: \(error.localizedDescription)")
        }
    }

    func importLayoutBackup(from url: URL) async {
        let isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()

        defer {
            if isAccessingSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        isLoading = true
        errorMessage = nil

        do {
            var snapshot = try await layoutStore.load(from: url)
            snapshot.settings = snapshot.settings.sanitized()
            let scannedApps = try await scanner.scanApplications(
                additionalDirectoryPaths: snapshot.settings.customApplicationDirectoryPaths
            )
            let appliedLayout = layoutStore.applying(snapshot, to: scannedApps)

            layoutSettings = settingsByUpdatingGrid(snapshot.settings)
            apps = appliedLayout.apps
            folders = appliedLayout.folders
            orderedItemIDs = appliedLayout.orderedItemIDs
            hasLoadedLayout = true
            currentPage = snapshot.settings.remembersLastPage && !isVerticalBrowsing ? snapshot.currentPage : 0
            currentPage = min(currentPage, pageCount - 1)
            selectedItemID = visibleItems.first?.id
            layoutWarningMessage = String(localized: "Backup imported.")
            saveCurrentLayout()
        } catch {
            layoutWarningMessage = String(localized: "Backup could not be imported: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func clearLayoutMessage() {
        layoutWarningMessage = nil
    }

    func compactLayout() {
        orderedItemIDs = normalizedTopLevelItemIDs()
        selectAfterLayoutChange()
        layoutWarningMessage = "布局已重新整理。"
        saveCurrentLayout()
    }

    func refreshIconCache() {
        AppIconCache.removeAll()
        iconRefreshToken = UUID()
        layoutWarningMessage = String(localized: "Icon cache refreshed.")
    }

    func exportDiagnostics(to url: URL) async {
        let isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()

        defer {
            if isAccessingSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let diagnostics = """
            LaunchOS Diagnostics
            Generated: \(Date())
            App Count: \(apps.count)
            Visible Item Count: \(visibleItems.count)
            Folder Count: \(folders.count)
            Hidden App Count: \(hiddenApps.count)
            Current Page: \(currentPage + 1) / \(pageCount)
            Browsing Mode: \(layoutSettings.browsingMode.rawValue)
            Grid: \(layoutSettings.lastKnownColumns)x\(layoutSettings.lastKnownRows)
            Custom Sources:
            \(layoutSettings.customApplicationDirectoryPaths.joined(separator: "\n"))
            """

            try diagnostics.write(to: url, atomically: true, encoding: .utf8)
            layoutWarningMessage = "诊断日志已导出。"
        } catch {
            layoutWarningMessage = "诊断日志导出失败：\(error.localizedDescription)"
        }
    }

    func resetPagingForSearch() {
        openedFolderID = nil
        folderDropTargetID = nil
        currentPage = 0
        selectedItemID = visibleItems.first?.id
    }

    func nextPage() {
        guard !isVerticalBrowsing else {
            return
        }

        currentPage = min(currentPage + 1, pageCount - 1)
        selectedItemID = currentPageItems.first?.id
        saveCurrentPageIfBrowsing()
    }

    func previousPage() {
        guard !isVerticalBrowsing else {
            return
        }

        currentPage = max(currentPage - 1, 0)
        selectedItemID = currentPageItems.first?.id
        saveCurrentPageIfBrowsing()
    }

    func moveSelection(by offset: Int) {
        guard !visibleItems.isEmpty else {
            selectedItemID = nil
            return
        }

        let fallbackIndex = min(currentPage * itemsPerPage, visibleItems.count - 1)
        let currentIndex = selectedItemID
            .flatMap { id in visibleItems.firstIndex { $0.id == id } }
            ?? fallbackIndex
        let nextIndex = min(max(currentIndex + offset, 0), visibleItems.count - 1)

        selectedItemID = visibleItems[nextIndex].id
        currentPage = isVerticalBrowsing ? 0 : nextIndex / max(1, itemsPerPage)
        saveCurrentPageIfBrowsing()
    }

    func beginDragging(_ appID: AppRecord.ID) {
        guard canReorderApps, topLevelAppIDs().contains(appID) else {
            draggingAppID = nil
            draggingSourceFolderID = nil
            dragPreviewState = nil
            dragRestoreState = nil
            return
        }

        captureDragRestoreStateIfNeeded()
        draggingAppID = appID
        draggingSourceFolderID = nil
        selectedItemID = appID
    }

    func beginDraggingFolderApp(_ appID: AppRecord.ID, in folderID: LauncherFolder.ID) {
        guard
            canReorderApps,
            let folder = folders.first(where: { $0.id == folderID }),
            folder.appIDs.contains(appID)
        else {
            draggingAppID = nil
            draggingSourceFolderID = nil
            dragPreviewState = nil
            dragRestoreState = nil
            return
        }

        captureDragRestoreStateIfNeeded()
        draggingAppID = appID
        draggingSourceFolderID = folderID
        selectedItemID = appID
    }

    func updateDragPreview(
        appID: AppRecord.ID,
        locationInWindow: CGPoint,
        cursorOffsetFromCenter: CGSize
    ) {
        guard draggingAppID == appID else {
            return
        }

        dragPreviewState = AppDragPreviewState(
            appID: appID,
            locationInWindow: locationInWindow,
            cursorOffsetFromCenter: cursorOffsetFromCenter
        )
    }

    func moveDraggingApp(over targetItemID: LauncherItem.ID) {
        guard canReorderApps, draggingSourceFolderID == nil, let draggingAppID, draggingAppID != targetItemID else {
            return
        }

        clearFolderDropTarget()
        moveTopLevelItem(draggingAppID, over: targetItemID)
    }

    func moveDraggingFolderApp(over targetAppID: AppRecord.ID, in folderID: LauncherFolder.ID) {
        guard
            canReorderApps,
            draggingSourceFolderID == folderID,
            let draggingAppID,
            draggingAppID != targetAppID,
            let folderIndex = folders.firstIndex(where: { $0.id == folderID }),
            let sourceIndex = folders[folderIndex].appIDs.firstIndex(of: draggingAppID),
            let targetIndex = folders[folderIndex].appIDs.firstIndex(of: targetAppID)
        else {
            return
        }

        let movedAppID = folders[folderIndex].appIDs.remove(at: sourceIndex)
        folders[folderIndex].appIDs.insert(movedAppID, at: min(targetIndex, folders[folderIndex].appIDs.count))
        folders[folderIndex].updatedAt = Date()
        selectedItemID = movedAppID
    }

    func moveDraggingFolderAppToTopLevel(over targetItemID: LauncherItem.ID? = nil) {
        guard
            canReorderApps,
            let draggingAppID,
            let sourceFolderID = draggingSourceFolderID,
            apps.contains(where: { $0.id == draggingAppID && !$0.isHidden }),
            let folderIndex = folders.firstIndex(where: { $0.id == sourceFolderID }),
            folders[folderIndex].appIDs.contains(draggingAppID)
        else {
            return
        }

        let previousTopLevelItemIDs = normalizedTopLevelItemIDs()
        let fallbackIndex = previousTopLevelItemIDs.firstIndex(of: sourceFolderID)
            .map { $0 + 1 }
            ?? previousTopLevelItemIDs.count

        folders[folderIndex].appIDs.removeAll { $0 == draggingAppID }
        folders[folderIndex].updatedAt = Date()

        var itemIDs = previousTopLevelItemIDs.filter { $0 != draggingAppID }
        let insertionIndex = targetItemID
            .flatMap { itemIDs.firstIndex(of: $0) }
            ?? min(fallbackIndex, itemIDs.count)

        itemIDs.insert(draggingAppID, at: min(insertionIndex, itemIDs.count))
        orderedItemIDs = itemIDs
        draggingSourceFolderID = nil
        openedFolderID = nil

        dissolveFolderIfNeeded(sourceFolderID)
        selectVisibleItem(draggingAppID)
    }

    func previewFolderDrop(on targetItemID: LauncherItem.ID, activatesImmediately: Bool = false) {
        guard canReorderApps, draggingSourceFolderID == nil, draggingAppID != nil else {
            clearFolderDropTarget()
            return
        }

        if activatesImmediately {
            folderDropPreviewTask?.cancel()
            folderDropPreviewTask = nil
            pendingFolderDropTargetID = nil
            folderDropTargetID = targetItemID
            return
        }

        guard folderDropTargetID != targetItemID, pendingFolderDropTargetID != targetItemID else {
            return
        }

        pendingFolderDropTargetID = targetItemID
        folderDropPreviewTask?.cancel()
        folderDropPreviewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 240_000_000)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard
                    let self,
                    self.canReorderApps,
                    self.draggingAppID != nil,
                    self.pendingFolderDropTargetID == targetItemID
                else {
                    return
                }

                self.folderDropTargetID = targetItemID
            }
        }
    }

    func clearFolderDropTarget(for targetItemID: LauncherItem.ID? = nil) {
        guard
            targetItemID == nil
                || pendingFolderDropTargetID == targetItemID
                || folderDropTargetID == targetItemID
        else {
            return
        }

        folderDropPreviewTask?.cancel()
        folderDropPreviewTask = nil
        pendingFolderDropTargetID = nil

        if targetItemID == nil || folderDropTargetID == targetItemID {
            folderDropTargetID = nil
        }
    }

    func canGroupDraggingApp(with targetItem: LauncherItem) -> Bool {
        guard canReorderApps, draggingSourceFolderID == nil, let draggingAppID, draggingAppID != targetItem.id else {
            return false
        }

        switch targetItem.kind {
        case .app:
            return targetItem.app != nil
        case .folder:
            return targetItem.folder != nil
        }
    }

    func groupDraggingApp(with targetItem: LauncherItem) {
        guard canGroupDraggingApp(with: targetItem), let draggingAppID else {
            return
        }

        clearFolderDropTarget()

        switch targetItem.kind {
        case .app:
            guard let targetApp = targetItem.app else {
                return
            }

            createFolder(draggingAppID: draggingAppID, targetAppID: targetApp.id)
        case .folder:
            guard let folder = targetItem.folder else {
                return
            }

            addApp(draggingAppID, toFolder: folder.id)
        }
    }

    func moveDraggingAppToEnd() {
        guard canReorderApps, draggingSourceFolderID == nil, let draggingAppID else {
            return
        }

        clearFolderDropTarget()

        var itemIDs = normalizedTopLevelItemIDs()

        guard itemIDs.contains(draggingAppID) else {
            return
        }

        itemIDs.removeAll { $0 == draggingAppID }
        itemIDs.append(draggingAppID)
        orderedItemIDs = itemIDs
        selectVisibleItem(draggingAppID)
    }

    func finishDragging(saveChanges: Bool = true) {
        guard draggingAppID != nil else {
            draggingSourceFolderID = nil
            dragPreviewState = nil
            clearFolderDropTarget()
            dragRestoreState = nil
            return
        }

        draggingAppID = nil
        draggingSourceFolderID = nil
        dragPreviewState = nil
        clearFolderDropTarget()
        dragRestoreState = nil

        if saveChanges {
            saveCurrentLayout()
        }
    }

    func cancelDraggingRestoringLayout() {
        if let dragRestoreState {
            folders = dragRestoreState.folders
            orderedItemIDs = dragRestoreState.orderedItemIDs
            currentPage = min(dragRestoreState.currentPage, pageCount - 1)
            selectedItemID = dragRestoreState.selectedItemID
            openedFolderID = dragRestoreState.openedFolderID
        }

        draggingAppID = nil
        draggingSourceFolderID = nil
        dragPreviewState = nil
        clearFolderDropTarget()
        dragRestoreState = nil
    }

    func launch(_ item: LauncherItem) {
        switch item.kind {
        case .app:
            if let app = item.app {
                launch(app)
            }
        case .folder:
            if let folder = item.folder {
                openFolder(folder.id)
            }
        }
    }

    func launch(_ app: AppRecord) {
        Task {
            do {
                try await launcher.open(app)
                markOpened(app)
                LauncherWindowController.hideLauncher()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func launchSelectedOrFirstResult() {
        let item = selectedItemID.flatMap { id in
            visibleItems.first { $0.id == id }
        } ?? visibleItems.first

        if let item {
            launch(item)
        }
    }

    func openFolder(_ folderID: LauncherFolder.ID) {
        guard folders.contains(where: { $0.id == folderID }) else {
            openedFolderID = nil
            return
        }

        openedFolderID = folderID
        selectedItemID = folderID
    }

    func closeFolder() {
        openedFolderID = nil
    }

    func requestRenameFolder(_ folderID: LauncherFolder.ID) {
        guard let folder = folders.first(where: { $0.id == folderID }) else {
            folderRenameRequest = nil
            return
        }

        folderRenameRequest = FolderRenameRequest(id: folder.id, currentName: folder.name)
    }

    func renameFolder(_ folderID: LauncherFolder.ID, to name: String) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        folders[folderIndex].name = trimmedName
        folders[folderIndex].updatedAt = Date()
        folderRenameRequest = nil
        saveCurrentLayout()
    }

    func requestDissolveFolder(_ folderID: LauncherFolder.ID) {
        guard let folder = folders.first(where: { $0.id == folderID }) else {
            folderDissolveRequest = nil
            return
        }

        folderDissolveRequest = FolderDissolveRequest(
            id: folder.id,
            name: folder.name,
            appCount: apps(in: folder).count
        )
    }

    func confirmDissolveRequestedFolder() {
        guard let request = folderDissolveRequest else {
            return
        }

        folderDissolveRequest = nil
        dissolveFolder(request.id)
    }

    func cancelDissolveFolder() {
        folderDissolveRequest = nil
    }

    func dissolveFolder(_ folderID: LauncherFolder.ID) {
        dissolveFolder(folderID, saveChanges: true)
    }

    func requestAppAlias(_ appID: AppRecord.ID) {
        guard let app = apps.first(where: { $0.id == appID }) else {
            appAliasRequest = nil
            return
        }

        appAliasRequest = AppAliasRequest(
            id: app.id,
            displayName: app.displayName,
            currentAlias: app.alias ?? ""
        )
    }

    func renameAppAlias(_ appID: AppRecord.ID, to alias: String) {
        guard let appIndex = apps.firstIndex(where: { $0.id == appID }) else {
            return
        }

        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        apps[appIndex].alias = trimmedAlias.isEmpty ? nil : trimmedAlias
        appAliasRequest = nil
        saveCurrentLayout()
    }

    func showInFinder(_ app: AppRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    func moveApp(_ appID: AppRecord.ID, toFolder folderID: LauncherFolder.ID) {
        guard
            apps.contains(where: { $0.id == appID }),
            folders.contains(where: { $0.id == folderID })
        else {
            return
        }

        removeAppFromContainingFolder(appID)

        var itemIDs = normalizedTopLevelItemIDs()
        itemIDs.removeAll { $0 == appID }

        guard let destinationIndex = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }

        guard !folders[destinationIndex].appIDs.contains(appID) else {
            return
        }

        folders[destinationIndex].appIDs.append(appID)
        folders[destinationIndex].updatedAt = Date()
        orderedItemIDs = itemIDs
        openFolder(folderID)
        saveCurrentLayout()
    }

    func hideApp(_ appID: AppRecord.ID) {
        guard let appIndex = apps.firstIndex(where: { $0.id == appID }) else {
            return
        }

        apps[appIndex].isHidden = true
        removeAppFromContainingFolder(appID)
        orderedItemIDs = normalizedTopLevelItemIDs()
        selectAfterLayoutChange()
        saveCurrentLayout()
    }

    func restoreApp(_ appID: AppRecord.ID) {
        guard let appIndex = apps.firstIndex(where: { $0.id == appID }) else {
            return
        }

        apps[appIndex].isHidden = false
        orderedItemIDs = normalizedTopLevelItemIDs()
        selectVisibleItem(appID)
        saveCurrentLayout()
    }

    func restoreAllHiddenApps() {
        let firstHiddenAppID = hiddenApps.first?.id

        guard firstHiddenAppID != nil else {
            return
        }

        for index in apps.indices where apps[index].isHidden {
            apps[index].isHidden = false
        }

        orderedItemIDs = normalizedTopLevelItemIDs()
        selectAfterLayoutChange(preferredItemID: firstHiddenAppID)
        saveCurrentLayout()
    }

    private func markOpened(_ app: AppRecord) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else {
            return
        }

        apps[index].lastOpenedAt = Date()
        saveCurrentLayout()
    }

    private func moveTopLevelItem(_ draggedItemID: LauncherItem.ID, over targetItemID: LauncherItem.ID) {
        var itemIDs = normalizedTopLevelItemIDs()

        guard
            let sourceIndex = itemIDs.firstIndex(of: draggedItemID),
            let targetIndex = itemIDs.firstIndex(of: targetItemID)
        else {
            return
        }

        let draggedItemID = itemIDs.remove(at: sourceIndex)
        itemIDs.insert(draggedItemID, at: min(targetIndex, itemIDs.count))
        orderedItemIDs = itemIDs
        selectVisibleItem(draggedItemID)
    }

    private func createFolder(draggingAppID: AppRecord.ID, targetAppID: AppRecord.ID) {
        var itemIDs = normalizedTopLevelItemIDs()
        var folderAppIDs: [AppRecord.ID] = []

        for appID in [targetAppID, draggingAppID] where !folderAppIDs.contains(appID) {
            guard apps.contains(where: { $0.id == appID && !$0.isHidden }) else {
                continue
            }

            folderAppIDs.append(appID)
        }

        guard
            folderAppIDs.count > 1,
            itemIDs.contains(draggingAppID),
            let targetIndex = itemIDs.firstIndex(of: targetAppID)
        else {
            return
        }

        let insertionIndex = itemIDs[..<targetIndex]
            .filter { $0 != draggingAppID && $0 != targetAppID }
            .count
        let folder = LauncherFolder(name: nextFolderName(), appIDs: folderAppIDs)

        itemIDs.removeAll { $0 == draggingAppID || $0 == targetAppID }
        itemIDs.insert(folder.id, at: min(insertionIndex, itemIDs.count))

        folders.append(folder)
        orderedItemIDs = itemIDs
        openFolder(folder.id)
    }

    private func addApp(_ appID: AppRecord.ID, toFolder folderID: LauncherFolder.ID) {
        guard
            let folderIndex = folders.firstIndex(where: { $0.id == folderID }),
            !folders[folderIndex].appIDs.contains(appID)
        else {
            return
        }

        var itemIDs = normalizedTopLevelItemIDs()
        itemIDs.removeAll { $0 == appID }
        folders[folderIndex].appIDs.append(appID)
        folders[folderIndex].updatedAt = Date()
        orderedItemIDs = itemIDs
        openFolder(folderID)
    }

    @discardableResult
    private func removeAppFromContainingFolder(_ appID: AppRecord.ID) -> LauncherFolder.ID? {
        guard let folderIndex = folders.firstIndex(where: { $0.appIDs.contains(appID) }) else {
            return nil
        }

        let folderID = folders[folderIndex].id
        folders[folderIndex].appIDs.removeAll { $0 == appID }
        folders[folderIndex].updatedAt = Date()
        dissolveFolderIfNeeded(folderID)
        return folderID
    }

    private func dissolveFolderIfNeeded(_ folderID: LauncherFolder.ID) {
        guard let folder = folders.first(where: { $0.id == folderID }), apps(in: folder).count <= 1 else {
            return
        }

        dissolveFolder(folderID, saveChanges: false)
    }

    private func dissolveFolder(_ folderID: LauncherFolder.ID, saveChanges: Bool) {
        var itemIDs = normalizedTopLevelItemIDs()

        guard
            let folderIndex = folders.firstIndex(where: { $0.id == folderID }),
            let folderItemIndex = itemIDs.firstIndex(of: folderID)
        else {
            return
        }

        let folder = folders.remove(at: folderIndex)
        let returnedAppIDs = folder.appIDs.filter { appID in
            apps.contains { $0.id == appID && !$0.isHidden }
        }

        itemIDs.removeAll { $0 == folderID || returnedAppIDs.contains($0) }
        itemIDs.insert(contentsOf: returnedAppIDs, at: min(folderItemIndex, itemIDs.count))
        orderedItemIDs = itemIDs

        if openedFolderID == folderID {
            openedFolderID = nil
        }

        selectAfterLayoutChange(preferredItemID: returnedAppIDs.first)

        if saveChanges {
            saveCurrentLayout()
        }
    }

    private func selectVisibleItem(_ itemID: LauncherItem.ID) {
        selectedItemID = itemID

        if let visibleIndex = visibleItems.firstIndex(where: { $0.id == itemID }) {
            currentPage = isVerticalBrowsing ? 0 : visibleIndex / max(1, itemsPerPage)
        }
    }

    private func selectAfterLayoutChange(preferredItemID: LauncherItem.ID? = nil) {
        currentPage = isVerticalBrowsing ? 0 : min(currentPage, pageCount - 1)

        if let preferredItemID, visibleItems.contains(where: { $0.id == preferredItemID }) {
            selectVisibleItem(preferredItemID)
            return
        }

        selectedItemID = currentPageItems.first?.id ?? visibleItems.first?.id
    }

    private func loadSavedLayout() async -> LauncherLayoutSnapshot {
        do {
            return try await layoutStore.load()
        } catch {
            layoutWarningMessage = String(
                localized: "Layout data could not be loaded, so LaunchOS started with a fresh layout."
            )
            return .empty
        }
    }

    private func saveCurrentPageIfBrowsing() {
        guard searchText.isEmpty, !isVerticalBrowsing else {
            return
        }

        saveCurrentLayout()
    }

    private func updateLayoutSettings(_ transform: (inout LayoutSettings) -> Void) {
        var settings = layoutSettings
        transform(&settings)
        settings.sanitize()

        guard settings != layoutSettings else {
            return
        }

        layoutSettings = settings

        if layoutSettings.browsingMode == .verticalScroll || !layoutSettings.remembersLastPage {
            currentPage = 0
        } else {
            currentPage = min(currentPage, pageCount - 1)
        }

        saveCurrentLayout()
    }

    private func saveCurrentLayout() {
        guard hasLoadedLayout || !apps.isEmpty else {
            return
        }

        orderedItemIDs = normalizedTopLevelItemIDs()
        let snapshot = currentLayoutSnapshot()

        Task {
            do {
                try await layoutStore.save(snapshot)
            } catch {
                await MainActor.run {
                    layoutWarningMessage = String(
                        localized: "Layout data could not be saved: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func captureDragRestoreStateIfNeeded() {
        guard dragRestoreState == nil else {
            return
        }

        dragRestoreState = DragRestoreState(
            folders: folders,
            orderedItemIDs: normalizedTopLevelItemIDs(),
            currentPage: currentPage,
            selectedItemID: selectedItemID,
            openedFolderID: openedFolderID
        )
    }

    private func currentLayoutSnapshot() -> LauncherLayoutSnapshot {
        layoutStore.snapshot(
            apps: apps,
            folders: folders,
            orderedItemIDs: normalizedTopLevelItemIDs(),
            currentPage: isVerticalBrowsing ? 0 : currentPage,
            settings: layoutSettings.sanitized()
        )
    }

    private func topLevelItems() -> [LauncherItem] {
        let appsByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        let folderItemsByID = Dictionary(uniqueKeysWithValues: folders.map { folder in
            (folder.id, LauncherItem.folder(folder, apps: apps(in: folder)))
        })

        return normalizedTopLevelItemIDs().compactMap { itemID in
            if let folderItem = folderItemsByID[itemID], !folderItem.folderApps.isEmpty {
                return folderItem
            }

            guard let app = appsByID[itemID], !app.isHidden else {
                return nil
            }

            return LauncherItem.app(app)
        }
    }

    private func topLevelAppIDs() -> [AppRecord.ID] {
        let folderedAppIDs = Set(folders.flatMap(\.appIDs))

        return apps
            .filter { !$0.isHidden && !folderedAppIDs.contains($0.id) }
            .map(\.id)
    }

    private func normalizedTopLevelItemIDs() -> [LauncherItem.ID] {
        let appIDs = topLevelAppIDs()
        let folderIDs = folders.map(\.id)
        let validItemIDs = Set(appIDs + folderIDs)
        var usedItemIDs: Set<LauncherItem.ID> = []
        var itemIDs: [LauncherItem.ID] = []

        for itemID in orderedItemIDs where validItemIDs.contains(itemID) && !usedItemIDs.contains(itemID) {
            itemIDs.append(itemID)
            usedItemIDs.insert(itemID)
        }

        for folderID in folderIDs where !usedItemIDs.contains(folderID) {
            itemIDs.append(folderID)
            usedItemIDs.insert(folderID)
        }

        for appID in appIDs where !usedItemIDs.contains(appID) {
            itemIDs.append(appID)
            usedItemIDs.insert(appID)
        }

        return itemIDs
    }

    private func apps(in folder: LauncherFolder) -> [AppRecord] {
        let appsByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })

        return folder.appIDs.compactMap { appID in
            guard let app = appsByID[appID], !app.isHidden else {
                return nil
            }

            return app
        }
    }

    private func nextFolderName() -> String {
        let baseName = String(localized: "Folder")
        let usedNames = Set(folders.map(\.name))

        guard usedNames.contains(baseName) else {
            return baseName
        }

        var index = folders.count + 1

        while usedNames.contains("\(baseName) \(index)") {
            index += 1
        }

        return "\(baseName) \(index)"
    }

    private func settingsByUpdatingGrid(_ settings: LayoutSettings) -> LayoutSettings {
        let rows = max(1, Int(ceil(Double(itemsPerPage) / Double(max(1, columnCount)))))

        var updatedSettings = settings
        updatedSettings.lastKnownColumns = columnCount
        updatedSettings.lastKnownRows = rows
        updatedSettings.lastKnownItemsPerPage = itemsPerPage
        updatedSettings.sanitize()
        return updatedSettings
    }
}
