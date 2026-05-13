import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: LauncherModel
    @Bindable var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool
    @State private var pagingDragOffset: CGFloat = 0
    @State private var lastInteractiveGridTapDate = Date.distantPast
    @State private var desktopWallpaperImage: NSImage?

    var body: some View {
        GeometryReader { geometry in
            let metrics = gridMetrics(for: geometry.size)

            ZStack {
                launcherBackdrop
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if model.openedFolderID != nil {
                            model.closeFolder()
                        } else {
                            LauncherWindowController.hideLauncher()
                        }
                    }
                    .contextMenu {
                        Button {
                            SettingsWindowController.showSettings()
                        } label: {
                            Label("Open Settings", systemImage: "gearshape")
                        }

                        Button {
                            Task {
                                await model.refreshApps()
                            }
                        } label: {
                            Label("Refresh Apps", systemImage: "arrow.clockwise")
                        }

                        Button {
                            model.refreshIconCache()
                        } label: {
                            Label("Refresh Icons", systemImage: "app.badge")
                        }
                    }

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        LauncherWindowController.hideLauncher()
                    }

                if #available(macOS 26.0, *) {
                    GlassEffectContainer(spacing: 18) {
                        launcherContent(metrics: metrics)
                    }
                } else {
                    launcherContent(metrics: metrics)
                }

                if let folder = model.openedFolder {
                    Rectangle()
                        .fill(.black.opacity(colorScheme == .dark ? 0.26 : 0.12))
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .transition(.opacity)
                        .onTapGesture {
                            model.closeFolder()
                        }

                    FolderOverlayView(
                        folder: folder,
                        model: model
                    )
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
                }

                if let dragPreviewState = model.dragPreviewState,
                   let draggingApp = model.draggingApp {
                    dragPreview(
                        for: draggingApp,
                        state: dragPreviewState,
                        containerSize: geometry.size
                    )
                    .zIndex(40)
                }
            }
            .background {
                ZStack {
                    BlankClickDismissMonitorView(
                        isEnabled: model.openedFolderID == nil,
                        onBlankClick: dismissLauncherFromBlankTap
                    )

                    ScrollWheelPagingView(
                        isEnabled: canUseGesturePaging,
                        onLiveOffsetChange: updateScrollPagingOffset(_:),
                        onLiveOffsetEnd: finishScrollPaging(_:),
                        onPage: turnPage(_:)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.currentPage)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.openedFolderID)
            .onAppear {
                refreshDesktopWallpaperImage()
                model.updateGrid(columns: metrics.columns, itemsPerPage: metrics.itemsPerPage)
                isSearchFocused = true
            }
            .onChange(of: geometry.size) { _, newSize in
                let newMetrics = gridMetrics(for: newSize)
                model.updateGrid(columns: newMetrics.columns, itemsPerPage: newMetrics.itemsPerPage)
            }
            .onChange(of: model.layoutSettings) {
                let newMetrics = gridMetrics(for: geometry.size)
                model.updateGrid(columns: newMetrics.columns, itemsPerPage: newMetrics.itemsPerPage)
            }
        }
        .task {
            await model.refreshAppsIfNeeded()
        }
        .onChange(of: model.searchText) {
            model.resetPagingForSearch()
        }
        .onChange(of: settingsStore.settings.backgroundStyle) {
            refreshDesktopWallpaperImage()
        }
        .onExitCommand {
            if model.openedFolderID != nil {
                model.closeFolder()
            } else if model.searchText.isEmpty {
                LauncherWindowController.hideLauncher()
            } else {
                model.searchText = ""
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                model.moveSelection(by: -1)
            case .right:
                model.moveSelection(by: 1)
            case .up:
                model.moveSelection(by: -model.columnCount)
            case .down:
                model.moveSelection(by: model.columnCount)
            @unknown default:
                break
            }
        }
        .sheet(item: $model.folderRenameRequest) { request in
            NameEditSheetView(
                title: String(localized: "Rename Folder"),
                placeholder: String(localized: "Folder name"),
                initialValue: request.currentName,
                commitTitle: String(localized: "Rename")
            ) { name in
                model.renameFolder(request.id, to: name)
            }
        }
        .sheet(item: $model.appAliasRequest) { request in
            NameEditSheetView(
                title: String(localized: "Rename App"),
                placeholder: request.displayName,
                initialValue: request.currentAlias,
                commitTitle: String(localized: "Save"),
                allowsEmptyValue: true
            ) { alias in
                model.renameAppAlias(request.id, to: alias)
            }
        }
        .confirmationDialog(
            String(localized: "Dissolve Folder?"),
            isPresented: Binding(
                get: { model.folderDissolveRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        model.cancelDissolveFolder()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let request = model.folderDissolveRequest {
                Button("Dissolve \(request.name)", role: .destructive) {
                    model.confirmDissolveRequestedFolder()
                }
            }

            Button("Cancel", role: .cancel) {
                model.cancelDissolveFolder()
            }
        } message: {
            if let request = model.folderDissolveRequest {
                Text("\(request.appCount) apps will return to the main grid.")
            }
        }
    }

    @ViewBuilder
    private var launcherBackdrop: some View {
        ZStack {
            switch settingsStore.settings.backgroundStyle {
            case .systemWallpaper:
                desktopWallpaperLayer
                    .blur(radius: settingsStore.settings.isWallpaperBlurred ? 30 : 0)
                    .scaleEffect(settingsStore.settings.isWallpaperBlurred ? 1.06 : 1)

                if settingsStore.settings.isWallpaperBlurred {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                }

                Rectangle()
                    .fill(systemWallpaperTint)
            case .frostedGlass:
                desktopWallpaperLayer
                    .blur(radius: frostedGlassBlurRadius)
                    .scaleEffect(frostedGlassWallpaperScale)
                    .saturation(frostedGlassSaturation)
                    .brightness(frostedGlassBrightness)
                    .contrast(frostedGlassContrast)

                Rectangle()
                    .fill(frostedGlassWash)

                Rectangle()
                    .fill(frostedGlassTint)

                LinearGradient(
                    colors: [
                        Color.white.opacity(frostedGlassHighlightOpacity),
                        Color.white.opacity(frostedGlassBottomHighlightOpacity)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: settingsStore.settings.backgroundStyle)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: settingsStore.settings.isWallpaperBlurred)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: settingsStore.settings.glassMaterialStrength)
    }

    @ViewBuilder
    private var desktopWallpaperLayer: some View {
        GeometryReader { geometry in
            if let desktopWallpaperImage {
                Image(nsImage: desktopWallpaperImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                wallpaperColorField
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    private var wallpaperColorField: some View {
        LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.43, blue: 0.62),
                Color(red: 0.27, green: 0.48, blue: 0.58),
                Color(red: 0.30, green: 0.52, blue: 0.44)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            RadialGradient(
                colors: [
                    Color(red: 0.33, green: 0.62, blue: 0.86).opacity(0.46),
                    .clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 900
            )
            .blendMode(.screen)
        }
        .overlay {
            RadialGradient(
                colors: [
                    Color(red: 0.10, green: 0.27, blue: 0.33).opacity(0.40),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 60,
                endRadius: 980
            )
            .blendMode(.multiply)
        }
    }

    private var systemWallpaperTint: Color {
        if settingsStore.settings.isWallpaperBlurred {
            return Color.black.opacity(colorScheme == .dark ? 0.28 : 0.10)
        }

        return Color.black.opacity(colorScheme == .dark ? 0.18 : 0.03)
    }

    private var frostedGlassBlurRadius: CGFloat {
        CGFloat(settingsStore.settings.glassMaterialStrength) * 64
    }

    private var frostedGlassWallpaperScale: CGFloat {
        1 + CGFloat(settingsStore.settings.glassMaterialStrength) * 0.075
    }

    private var frostedGlassSaturation: Double {
        1 - settingsStore.settings.glassMaterialStrength * 0.62
    }

    private var frostedGlassBrightness: Double {
        colorScheme == .dark
            ? -settingsStore.settings.glassMaterialStrength * 0.12
            : settingsStore.settings.glassMaterialStrength * 0.08
    }

    private var frostedGlassContrast: Double {
        1 - settingsStore.settings.glassMaterialStrength * 0.18
    }

    private var frostedGlassWash: Color {
        let strength = settingsStore.settings.glassMaterialStrength

        if colorScheme == .dark {
            return Color.black.opacity(0.02 + strength * 0.36)
        }

        return Color.white.opacity(0.02 + strength * 0.46)
    }

    private var frostedGlassTint: Color {
        let strength = settingsStore.settings.glassMaterialStrength

        return Color(red: 0.24, green: 0.47, blue: 0.57)
            .opacity(colorScheme == .dark ? strength * 0.26 : strength * 0.18)
    }

    private var frostedGlassHighlightOpacity: Double {
        let strength = settingsStore.settings.glassMaterialStrength
        return colorScheme == .dark ? strength * 0.08 : strength * 0.22
    }

    private var frostedGlassBottomHighlightOpacity: Double {
        let strength = settingsStore.settings.glassMaterialStrength
        return colorScheme == .dark ? strength * 0.03 : strength * 0.08
    }

    private func launcherContent(metrics: GridMetrics) -> some View {
        VStack(spacing: 34) {
            searchBar

            if model.isLoading {
                loadingState
            } else if let errorMessage = model.errorMessage {
                errorState(errorMessage)
            } else if model.visibleItems.isEmpty {
                emptyState
            } else {
                appGrid(metrics: metrics)
                    .simultaneousGesture(pagingDragGesture)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
            }

            if !model.isVerticalBrowsing {
                pageControls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 32)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))

            TextField(
                "",
                text: $model.searchText,
                prompt: Text("搜索应用").foregroundStyle(.white.opacity(0.55))
            )
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .foregroundStyle(.white)
                .onSubmit {
                    model.launchSelectedOrFirstResult()
                }

            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.70))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
            }

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .font(.system(size: 17, weight: .semibold))
        .padding(.horizontal, 18)
        .frame(width: 300, height: 50)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: VisualStyle.searchRadius, style: .continuous))
        .launchOSGlassSurface(cornerRadius: VisualStyle.searchRadius, isInteractive: true, strokeOpacity: 0.28)
        .shadow(color: Color(red: 0.05, green: 0.18, blue: 0.27).opacity(0.18), radius: 20, y: 10)
        .simultaneousGesture(
            TapGesture().onEnded {
                noteInteractiveGridTap()
            }
        )
    }

    @ViewBuilder
    private func appGrid(metrics: GridMetrics) -> some View {
        if model.isVerticalBrowsing {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())

                ScrollView(.vertical) {
                    gridContent(items: model.visibleItems, metrics: metrics)
                }
                .scrollIndicators(.visible)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismissLauncherFromBlankTap()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            GeometryReader { geometry in
                let pageWidth = max(1, geometry.size.width)
                let effectiveOffset = effectivePagingOffset(for: pageWidth)

                ZStack(alignment: .top) {
                    Color.clear
                        .contentShape(Rectangle())

                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0..<model.pageCount, id: \.self) { page in
                            gridPage(page, metrics: metrics)
                                .frame(width: pageWidth, height: geometry.size.height, alignment: .top)
                                .opacity(pageOpacity(for: page, pageWidth: pageWidth, pagingOffset: effectiveOffset))
                                .scaleEffect(pageScale(for: page, pageWidth: pageWidth, pagingOffset: effectiveOffset))
                        }
                    }
                    .frame(
                        width: pageWidth * CGFloat(model.pageCount),
                        height: geometry.size.height,
                        alignment: .topLeading
                    )
                    .offset(x: -CGFloat(model.currentPage) * pageWidth + effectiveOffset)
                    .animation(pageTurnAnimation, value: model.currentPage)
                }
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissLauncherFromBlankTap()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func gridPage(_ page: Int, metrics: GridMetrics) -> some View {
        ZStack(alignment: .top) {
            if abs(page - model.currentPage) <= 1 {
                gridContent(items: items(forPage: page), metrics: metrics)
            }
        }
    }

    private func gridContent(items: [LauncherItem], metrics: GridMetrics) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(metrics.itemWidth), spacing: metrics.horizontalSpacing),
                count: metrics.columns
            ),
            spacing: metrics.verticalSpacing
        ) {
            ForEach(items) { item in
                gridItem(for: item)
            }
        }
        .padding(.horizontal, metrics.horizontalSpacing)
        .padding(.vertical, metrics.verticalSpacing)
        .frame(width: metrics.availableWidth, alignment: .top)
        .onDrop(of: [UTType.plainText], delegate: AppGridDropDelegate(model: model))
        .animation(reorderAnimation, value: items.map(\.id))
    }

    private func dragPreview(
        for app: AppRecord,
        state: AppDragPreviewState,
        containerSize: CGSize
    ) -> some View {
        AppDragPreviewView(
            app: app,
            iconRefreshToken: model.iconRefreshToken
        )
        .position(dragPreviewPosition(for: state, containerSize: containerSize))
        .allowsHitTesting(false)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
        .accessibilityHidden(true)
    }

    private func dragPreviewPosition(
        for state: AppDragPreviewState,
        containerSize: CGSize
    ) -> CGPoint {
        let centerX = state.locationInWindow.x - state.cursorOffsetFromCenter.width
        let centerYFromBottom = state.locationInWindow.y - state.cursorOffsetFromCenter.height

        return CGPoint(
            x: centerX,
            y: containerSize.height - centerYFromBottom
        )
    }

    private func items(forPage page: Int) -> [LauncherItem] {
        guard !model.isVerticalBrowsing else {
            return model.visibleItems
        }

        let safePage = min(max(page, 0), model.pageCount - 1)
        let startIndex = safePage * model.itemsPerPage
        let endIndex = min(startIndex + model.itemsPerPage, model.visibleItems.count)

        guard startIndex < endIndex else {
            return []
        }

        return Array(model.visibleItems[startIndex..<endIndex])
    }

    private func effectivePagingOffset(for pageWidth: CGFloat) -> CGFloat {
        let boundedOffset = max(-pageWidth, min(pageWidth, pagingDragOffset))

        if boundedOffset > 0, model.currentPage == 0 {
            return rubberBandedOffset(boundedOffset, pageWidth: pageWidth)
        }

        if boundedOffset < 0, model.currentPage >= model.pageCount - 1 {
            return -rubberBandedOffset(abs(boundedOffset), pageWidth: pageWidth)
        }

        return boundedOffset
    }

    private func rubberBandedOffset(_ offset: CGFloat, pageWidth: CGFloat) -> CGFloat {
        let limit = max(1, pageWidth)
        return (offset * 0.34) / (1 + offset / limit)
    }

    private func pageOpacity(for page: Int, pageWidth: CGFloat, pagingOffset: CGFloat) -> Double {
        guard !reduceMotion, page == model.currentPage, abs(pagingOffset) > 1 else {
            return 1
        }

        let progress = min(1, abs(pagingOffset) / max(1, pageWidth))
        return 1 - Double(progress) * 0.08
    }

    private func pageScale(for page: Int, pageWidth: CGFloat, pagingOffset: CGFloat) -> CGFloat {
        guard !reduceMotion, page == model.currentPage, abs(pagingOffset) > 1 else {
            return 1
        }

        let progress = min(1, abs(pagingOffset) / max(1, pageWidth))
        return 1 - progress * 0.018
    }

    private var pageTurnAnimation: Animation? {
        reduceMotion ? nil : .interpolatingSpring(mass: 0.9, stiffness: 230, damping: 31, initialVelocity: 0.22)
    }

    private var reorderAnimation: Animation? {
        reduceMotion ? nil : .interactiveSpring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.04)
    }

    private func updateManualDragTarget(_ item: LauncherItem, location: CGPoint) {
        guard model.canReorderApps, model.draggingAppID != nil else {
            return
        }

        if model.draggingSourceFolderID != nil {
            withAnimation(reorderAnimation) {
                model.moveDraggingFolderAppToTopLevel(over: item.id)
            }
            return
        }

        if isManualFolderDropTarget(item, at: location) {
            model.previewFolderDrop(on: item.id, activatesImmediately: item.kind == .folder)
        } else {
            model.clearFolderDropTarget(for: item.id)
            withAnimation(reorderAnimation) {
                model.moveDraggingApp(over: item.id)
            }
        }
    }

    private func performManualDragDrop(on item: LauncherItem, location: CGPoint) {
        guard model.canReorderApps else {
            model.finishDragging(saveChanges: false)
            return
        }

        if model.draggingSourceFolderID != nil {
            withAnimation(reorderAnimation) {
                model.moveDraggingFolderAppToTopLevel(over: item.id)
            }
            model.finishDragging()
            return
        }

        if (model.folderDropTargetID == item.id || isManualFolderDropTarget(item, at: location)),
           model.canGroupDraggingApp(with: item) {
            withAnimation(reorderAnimation) {
                model.groupDraggingApp(with: item)
            }
        }

        model.finishDragging()
    }

    private func isManualFolderDropTarget(_ item: LauncherItem, at location: CGPoint) -> Bool {
        guard model.canGroupDraggingApp(with: item) else {
            return false
        }

        switch item.kind {
        case .folder:
            return existingFolderDropHotZone.contains(location)
        case .app:
            return newFolderDropHotZone.contains(location)
        }
    }

    private var existingFolderDropHotZone: CGRect {
        CGRect(x: 0, y: 0, width: 156, height: 172)
    }

    private var newFolderDropHotZone: CGRect {
        CGRect(x: 12, y: 20, width: 132, height: 132)
    }

    @ViewBuilder
    private func gridItem(for item: LauncherItem) -> some View {
        switch item.kind {
        case .app:
            if let app = item.app {
                AppGridItemView(
                    app: app,
                    isSelected: model.selectedItemID == item.id,
                    isDragging: model.draggingAppID == app.id,
                    canReorder: model.canReorderApps,
                    isFolderDropTarget: model.folderDropTargetID == item.id,
                    iconRefreshToken: model.iconRefreshToken
                ) {
                    noteInteractiveGridTap()
                    model.launch(app)
                }
                .overlay {
                    NativeAppDragSourceView(
                        appID: app.id,
                        icon: AppIconCache.icon(for: app.path),
                        isEnabled: model.canReorderApps
                    ) {
                        model.beginDragging(app.id)
                    } finishDragging: {
                        model.finishDragging()
                    } launch: {
                        noteInteractiveGridTap()
                        model.launch(app)
                    } updateDraggingPreview: { locationInWindow, cursorOffsetFromCenter in
                        model.updateDragPreview(
                            appID: app.id,
                            locationInWindow: locationInWindow,
                            cursorOffsetFromCenter: cursorOffsetFromCenter
                        )
                    } hoverDragging: { location in
                        updateManualDragTarget(item, location: location)
                    } performDraggingDrop: { location in
                        performManualDragDrop(on: item, location: location)
                    }
                    .frame(width: 156, height: 172)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: AppReorderDropDelegate(targetItem: item, model: model)
                )
                .launcherAppContextMenu(for: app, model: model)
                .onHover { isHovering in
                    if isHovering {
                        model.selectedItemID = item.id
                    }
                }
            }
        case .folder:
            if let folder = item.folder {
                FolderGridItemView(
                    folder: folder,
                    apps: item.folderApps,
                    isSelected: model.selectedItemID == item.id,
                    isDropTarget: model.folderDropTargetID == item.id,
                    canReorder: model.canReorderApps,
                    iconRefreshToken: model.iconRefreshToken
                ) {
                    noteInteractiveGridTap()
                    model.openFolder(folder.id)
                }
                .overlay {
                    NativeAppDragSourceView(
                        appID: folder.id,
                        icon: NSImage(),
                        isEnabled: model.canReorderApps
                            && model.draggingAppID != nil
                            && model.draggingSourceFolderID == nil
                    ) {
                    } finishDragging: {
                        model.finishDragging()
                    } launch: {
                    } updateDraggingPreview: { _, _ in
                    } hoverDragging: { location in
                        updateManualDragTarget(item, location: location)
                    } performDraggingDrop: { location in
                        performManualDragDrop(on: item, location: location)
                    }
                    .frame(width: 156, height: 172)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: AppReorderDropDelegate(targetItem: item, model: model)
                )
                .launcherFolderContextMenu(for: folder, model: model)
                .onHover { isHovering in
                    if isHovering {
                        model.selectedItemID = item.id
                    }
                }
            }
        }
    }

    private var pageControls: some View {
        HStack(spacing: 7) {
            ForEach(0..<min(model.pageCount, 12), id: \.self) { page in
                Circle()
                    .fill(Color.white.opacity(pageIndicatorOpacity(for: page)))
                    .frame(width: 6, height: 6)
                    .scaleEffect(pageIndicatorScale(for: page))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: model.currentPage)
            }

            if model.pageCount > 12 {
                Text("\(model.currentPage + 1)/\(model.pageCount)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .monospacedDigit()
            }
        }
        .frame(minWidth: 96, minHeight: 18)
        .accessibilityLabel("Page \(model.currentPage + 1) of \(model.pageCount)")
    }

    private var pagingIndicatorProgress: CGFloat {
        min(1, abs(pagingDragOffset) / 150)
    }

    private var pagingPreviewTargetPage: Int? {
        guard abs(pagingDragOffset) > 12 else {
            return nil
        }

        if pagingDragOffset < 0, model.currentPage < model.pageCount - 1 {
            return model.currentPage + 1
        }

        if pagingDragOffset > 0, model.currentPage > 0 {
            return model.currentPage - 1
        }

        return nil
    }

    private func pageIndicatorOpacity(for page: Int) -> Double {
        if page == model.currentPage {
            return 0.88 - Double(pagingIndicatorProgress) * 0.18
        }

        if page == pagingPreviewTargetPage {
            return 0.34 + Double(pagingIndicatorProgress) * 0.42
        }

        return 0.34
    }

    private func pageIndicatorScale(for page: Int) -> CGFloat {
        if page == model.currentPage {
            return 1.18 - pagingIndicatorProgress * 0.12
        }

        if page == pagingPreviewTargetPage {
            return 1 + pagingIndicatorProgress * 0.18
        }

        return 1
    }

    private var canUseGesturePaging: Bool {
        !model.isVerticalBrowsing
            && model.openedFolderID == nil
            && model.draggingAppID == nil
            && model.searchText.isEmpty
            && model.pageCount > 1
    }

    private var pagingDragGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard canUseGesturePaging, isHorizontalSwipe(value.translation) else {
                    pagingDragOffset = 0
                    return
                }

                pagingDragOffset = value.translation.width
            }
            .onEnded { value in
                guard canUseGesturePaging, isHorizontalSwipe(value.translation) else {
                    withAnimation(pageTurnAnimation) {
                        pagingDragOffset = 0
                    }
                    return
                }

                let velocityWeightedWidth = value.translation.width
                    + (value.predictedEndTranslation.width - value.translation.width) * 0.28
                let turnThreshold: CGFloat = 84

                withAnimation(pageTurnAnimation) {
                    if velocityWeightedWidth <= -turnThreshold, model.currentPage < model.pageCount - 1 {
                        model.nextPage()
                    } else if velocityWeightedWidth >= turnThreshold, model.currentPage > 0 {
                        model.previousPage()
                    }

                    pagingDragOffset = 0
                }
            }
    }

    private func isHorizontalSwipe(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * 0.85
    }

    private func turnPage(_ direction: PagingDirection) {
        guard canUseGesturePaging else {
            return
        }

        switch direction {
        case .next:
            withAnimation(pageTurnAnimation) {
                model.nextPage()
            }
        case .previous:
            withAnimation(pageTurnAnimation) {
                model.previousPage()
            }
        }
    }

    private func refreshDesktopWallpaperImage() {
        desktopWallpaperImage = Self.loadDesktopWallpaperImage()
    }

    private static func loadDesktopWallpaperImage() -> NSImage? {
        let screen = NSScreen.main ?? NSScreen.screens.first

        guard
            let screen,
            let url = NSWorkspace.shared.desktopImageURL(for: screen)
        else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private func noteInteractiveGridTap() {
        lastInteractiveGridTapDate = Date()
    }

    private func dismissLauncherFromBlankTap() {
        let tapDate = Date()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            guard tapDate.timeIntervalSince(lastInteractiveGridTapDate) > 0.12 else {
                return
            }

            LauncherWindowController.hideLauncher()
        }
    }

    private func updateScrollPagingOffset(_ offset: CGFloat) {
        guard canUseGesturePaging else {
            pagingDragOffset = 0
            return
        }

        pagingDragOffset = offset
    }

    private func finishScrollPaging(_ direction: PagingDirection?) {
        guard canUseGesturePaging else {
            withAnimation(pageTurnAnimation) {
                pagingDragOffset = 0
            }
            return
        }

        withAnimation(pageTurnAnimation) {
            switch direction {
            case .next where model.currentPage < model.pageCount - 1:
                model.nextPage()
            case .previous where model.currentPage > 0:
                model.previousPage()
            default:
                break
            }

            pagingDragOffset = 0
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text("Scanning Applications")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.secondary)

            Text(model.searchText.isEmpty ? String(localized: "No apps found") : String(localized: "No results"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await model.refreshApps()
                }
            }
            .launchOSGlassButton(prominent: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gridMetrics(for size: CGSize) -> GridMetrics {
        let verticalChrome: CGFloat = 176
        let itemWidth: CGFloat = 156
        let itemHeight: CGFloat = 172
        let minimumGridSpacing: CGFloat = 28
        let availableWidth = max(360, size.width)
        let availableHeight = max(280, size.height - verticalChrome)
        let maximumFittingColumns = max(
            1,
            Int((availableWidth - minimumGridSpacing) / (itemWidth + minimumGridSpacing))
        )
        let automaticColumns = max(1, min(maximumFittingColumns, 7))
        let automaticRows = max(
            1,
            Int((availableHeight - minimumGridSpacing) / (itemHeight + minimumGridSpacing))
        )
        let settings = model.layoutSettings
        let columns = settings.usesCustomGrid
            ? min(settings.customColumnCount, maximumFittingColumns)
            : automaticColumns
        let rows = settings.usesCustomGrid ? settings.customRowCount : automaticRows
        let horizontalSpacing = max(
            minimumGridSpacing,
            (availableWidth - CGFloat(columns) * itemWidth) / CGFloat(columns + 1)
        )

        return GridMetrics(
            columns: columns,
            rows: rows,
            itemWidth: itemWidth,
            itemHeight: itemHeight,
            availableWidth: availableWidth,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: minimumGridSpacing
        )
    }
}

private struct AppDragPreviewView: View {
    let app: AppRecord
    let iconRefreshToken: UUID

    var body: some View {
        VStack(spacing: 14) {
            AppIconView(app: app, size: 118, refreshToken: iconRefreshToken)
                .scaleEffect(1.08)

            Text(app.alias ?? app.displayName)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.52), radius: 5, y: 2)
                .frame(width: 138, height: 40, alignment: .top)
        }
        .frame(width: 168, height: 184)
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(0.30), radius: 28, y: 18)
        .compositingGroup()
    }
}

private struct GridMetrics {
    let columns: Int
    let rows: Int
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let availableWidth: CGFloat
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    var itemsPerPage: Int {
        columns * rows
    }
}

private enum PagingDirection {
    case previous
    case next
}

private struct BlankClickDismissMonitorView: NSViewRepresentable {
    let isEnabled: Bool
    let onBlankClick: () -> Void

    func makeNSView(context: Context) -> BlankClickDismissNSView {
        let view = BlankClickDismissNSView()
        view.isEnabled = isEnabled
        view.onBlankClick = onBlankClick
        return view
    }

    func updateNSView(_ nsView: BlankClickDismissNSView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onBlankClick = onBlankClick
    }
}

private final class BlankClickDismissNSView: NSView {
    var isEnabled = false
    var onBlankClick: (() -> Void)?

    private var mouseMonitor: Any?
    private var mouseDownLocation: CGPoint?
    private var didDrag = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeMouseMonitor()
        } else {
            installMouseMonitorIfNeeded()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    deinit {
        removeMouseMonitor()
    }

    private func installMouseMonitorIfNeeded() {
        guard mouseMonitor == nil else {
            return
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard
                let self,
                self.isEnabled,
                let window = self.window,
                event.window === window
            else {
                return event
            }

            self.handleMouseEvent(event)
            return event
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownLocation = event.locationInWindow
            didDrag = false
        case .leftMouseDragged:
            guard let mouseDownLocation else {
                return
            }

            let deltaX = event.locationInWindow.x - mouseDownLocation.x
            let deltaY = event.locationInWindow.y - mouseDownLocation.y
            if hypot(deltaX, deltaY) > 6 {
                didDrag = true
            }
        case .leftMouseUp:
            guard mouseDownLocation != nil, !didDrag else {
                mouseDownLocation = nil
                didDrag = false
                return
            }

            mouseDownLocation = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                self?.onBlankClick?()
            }
        default:
            break
        }
    }

    private func removeMouseMonitor() {
        guard let mouseMonitor else {
            return
        }

        NSEvent.removeMonitor(mouseMonitor)
        self.mouseMonitor = nil
    }
}

private struct ScrollWheelPagingView: NSViewRepresentable {
    let isEnabled: Bool
    let onLiveOffsetChange: (CGFloat) -> Void
    let onLiveOffsetEnd: (PagingDirection?) -> Void
    let onPage: (PagingDirection) -> Void

    func makeNSView(context: Context) -> ScrollWheelPagingNSView {
        let view = ScrollWheelPagingNSView()
        view.isEnabled = isEnabled
        view.onLiveOffsetChange = onLiveOffsetChange
        view.onLiveOffsetEnd = onLiveOffsetEnd
        view.onPage = onPage
        return view
    }

    func updateNSView(_ nsView: ScrollWheelPagingNSView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onLiveOffsetChange = onLiveOffsetChange
        nsView.onLiveOffsetEnd = onLiveOffsetEnd
        nsView.onPage = onPage

        if !isEnabled {
            nsView.cancelLiveGesture()
        }
    }
}

private final class ScrollWheelPagingNSView: NSView {
    var isEnabled = false
    var onLiveOffsetChange: ((CGFloat) -> Void)?
    var onLiveOffsetEnd: ((PagingDirection?) -> Void)?
    var onPage: ((PagingDirection) -> Void)?
    private var scrollMonitor: Any?
    private var accumulatedPagingIntent: CGFloat = 0
    private var hasActivePreciseGesture = false
    private var lastDiscretePageDate = Date.distantPast
    private var phaseLessResetWorkItem: DispatchWorkItem?

    private let precisePagingThreshold: CGFloat = 32
    private let liveOffsetMultiplier: CGFloat = 2.35
    private let discretePagingThreshold: CGFloat = 4
    private let discretePagingCooldown: TimeInterval = 0.52
    private let phaseLessGestureResetDelay: TimeInterval = 0.18

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeScrollMonitor()
        } else {
            installScrollMonitorIfNeeded()
        }
    }

    deinit {
        removeScrollMonitor()
    }

    func cancelLiveGesture() {
        finishPreciseGesture(shouldCommit: false)
    }

    private func installScrollMonitorIfNeeded() {
        guard scrollMonitor == nil else {
            return
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
            guard
                let self,
                self.isEnabled,
                let window = self.window,
                event.window === window,
                self.bounds.contains(self.convert(event.locationInWindow, from: nil))
            else {
                return event
            }

            switch event.type {
            case .scrollWheel:
                return self.handleScroll(event) ? nil : event
            case .swipe:
                return self.handleSwipe(event) ? nil : event
            default:
                return event
            }
        }
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        if !event.momentumPhase.isEmpty {
            return true
        }

        guard let pagingIntent = pagingIntent(for: event) else {
            if event.hasPreciseScrollingDeltas, hasActivePreciseGesture {
                if event.phase.contains(.cancelled) {
                    finishPreciseGesture(shouldCommit: false)
                    return true
                }

                if event.phase.contains(.ended) {
                    finishPreciseGesture(shouldCommit: true)
                    return true
                }

                if event.phase.isEmpty {
                    schedulePhaseLessGestureFinish()
                    return true
                }
            }

            return false
        }

        if event.hasPreciseScrollingDeltas {
            handlePreciseScroll(pagingIntent, phase: event.phase)
            return true
        }

        handleDiscreteScroll(pagingIntent)
        return true
    }

    private func pagingIntent(for event: NSEvent) -> CGFloat? {
        let horizontalIntent = event.scrollingDeltaX == 0 ? event.deltaX : event.scrollingDeltaX
        let verticalIntent = abs(event.scrollingDeltaY == 0 ? event.deltaY : event.scrollingDeltaY)
        let minimumIntent: CGFloat = event.hasPreciseScrollingDeltas ? 0.45 : 2
        let verticalTolerance: CGFloat = event.hasPreciseScrollingDeltas ? 0.48 : 0.72

        guard abs(horizontalIntent) >= max(minimumIntent, verticalIntent * verticalTolerance) else {
            return nil
        }

        return horizontalIntent
    }

    private func handleSwipe(_ event: NSEvent) -> Bool {
        let horizontalIntent = event.deltaX
        let verticalIntent = abs(event.deltaY)

        guard abs(horizontalIntent) >= max(0.18, verticalIntent * 0.82) else {
            return false
        }

        let now = Date()
        guard now.timeIntervalSince(lastDiscretePageDate) >= discretePagingCooldown else {
            return true
        }

        finishPreciseGesture(shouldCommit: false)
        lastDiscretePageDate = now

        let direction: PagingDirection = horizontalIntent < 0 ? .next : .previous
        let previewOffset = direction == .next ? -precisePagingThreshold * liveOffsetMultiplier : precisePagingThreshold * liveOffsetMultiplier
        onLiveOffsetChange?(previewOffset)
        onLiveOffsetEnd?(direction)
        return true
    }

    private func handleDiscreteScroll(_ pagingIntent: CGFloat) {
        guard abs(pagingIntent) >= discretePagingThreshold else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastDiscretePageDate) >= discretePagingCooldown else {
            return
        }

        lastDiscretePageDate = now
        onPage?(pagingIntent > 0 ? .next : .previous)
    }

    private func handlePreciseScroll(_ pagingIntent: CGFloat, phase: NSEvent.Phase) {
        if !hasActivePreciseGesture {
            beginPreciseGesture()
        }

        accumulatedPagingIntent += pagingIntent
        onLiveOffsetChange?(-accumulatedPagingIntent * liveOffsetMultiplier)

        if phase.contains(.cancelled) {
            finishPreciseGesture(shouldCommit: false)
        } else if phase.contains(.ended) {
            finishPreciseGesture(shouldCommit: true)
        } else if phase.isEmpty {
            schedulePhaseLessGestureFinish()
        }
    }

    private func beginPreciseGesture() {
        phaseLessResetWorkItem?.cancel()
        phaseLessResetWorkItem = nil
        accumulatedPagingIntent = 0
        hasActivePreciseGesture = true
    }

    private func schedulePhaseLessGestureFinish() {
        phaseLessResetWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.finishPreciseGesture(shouldCommit: true)
        }

        phaseLessResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + phaseLessGestureResetDelay, execute: workItem)
    }

    private func finishPreciseGesture(shouldCommit: Bool) {
        guard hasActivePreciseGesture || accumulatedPagingIntent != 0 else {
            return
        }

        phaseLessResetWorkItem?.cancel()
        phaseLessResetWorkItem = nil

        let direction: PagingDirection?
        if shouldCommit, accumulatedPagingIntent >= precisePagingThreshold {
            direction = .next
        } else if shouldCommit, accumulatedPagingIntent <= -precisePagingThreshold {
            direction = .previous
        } else {
            direction = nil
        }

        if direction != nil {
            lastDiscretePageDate = Date()
        }

        onLiveOffsetEnd?(direction)
        accumulatedPagingIntent = 0
        hasActivePreciseGesture = false
    }

    private func removeScrollMonitor() {
        guard let scrollMonitor else {
            return
        }

        NSEvent.removeMonitor(scrollMonitor)
        self.scrollMonitor = nil
    }
}
