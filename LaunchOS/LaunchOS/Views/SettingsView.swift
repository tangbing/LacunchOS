import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var settingsStore: SettingsStore
    let launcherModel: LauncherModel
    let hotkeyService: HotkeyService
    let hotCornerService: HotCornerService

    @State private var selectedTab = SettingsTab.general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selectedTab: $selectedTab)

            Divider()

            ScrollView {
                selectedContent
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 760, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .general:
            generalContent
        case .interface:
            interfaceContent
        case .advanced:
            advancedContent
        case .about:
            aboutContent
        }
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSection(title: "启动") {
                SettingsCard {
                    SettingsRow(title: "开机自启动") {
                        Toggle("", isOn: $settingsStore.settings.isLaunchAtLoginEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }

            SettingsSection(title: "快捷键") {
                SettingsCard {
                    SettingsRow(title: "快捷键", subtitle: "打开或关闭 LaunchOS") {
                        HStack(spacing: 10) {
                            KeyCap("⌘⇧L")

                            Toggle("", isOn: $settingsStore.settings.isCommandShiftLHotkeyEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    SettingsDivider()

                    SettingsRow(title: "系统 F4 键", subtitle: hotkeyService.f4State.detail) {
                        HStack(spacing: 10) {
                            StatusBadge(text: hotkeyService.f4State.title)

                            Toggle("", isOn: $settingsStore.settings.isF4HotkeyEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    SettingsDivider()

                    SettingsRow(title: "触发角", subtitle: hotCornerService.status.detail) {
                        HStack(spacing: 10) {
                            Toggle("", isOn: $settingsStore.settings.isHotCornerEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)

                            Picker("", selection: $settingsStore.settings.hotCorner) {
                                ForEach(HotCorner.allCases) { corner in
                                    Text(corner.title).tag(corner)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 128)
                            .disabled(!settingsStore.settings.isHotCornerEnabled)
                        }
                    }
                }
            }

            SettingsSection(title: "外观") {
                SettingsCard {
                    SettingsRow(title: "显示菜单栏图标") {
                        Toggle("", isOn: $settingsStore.settings.showsMenuBarIcon)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    SettingsDivider()

                    SettingsRow(title: "App Icon", subtitle: "刷新系统缓存中的应用图标") {
                        Button("刷新图标") {
                            launcherModel.refreshIconCache()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var interfaceContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSection(title: "布局") {
                SettingsCard {
                    SettingsRow(title: "排序方式") {
                        Text("自定义")
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }

                    SettingsDivider()

                    SettingsRow(title: "浏览样式") {
                        Picker("", selection: browsingModeBinding) {
                            ForEach(LayoutSettings.BrowsingMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }

                    SettingsDivider()

                    SettingsRow(title: "网格布局") {
                        HStack(spacing: 10) {
                            Toggle("自定义", isOn: customGridEnabledBinding)
                                .toggleStyle(.switch)

                            Stepper(
                                "\(launcherModel.layoutSettings.customColumnCount)",
                                value: customColumnCountBinding,
                                in: LayoutSettings.minimumCustomColumns...LayoutSettings.maximumCustomColumns
                            )
                            .frame(width: 86)
                            .disabled(!launcherModel.layoutSettings.usesCustomGrid)

                            Text("×")
                                .foregroundStyle(.secondary)

                            Stepper(
                                "\(launcherModel.layoutSettings.customRowCount)",
                                value: customRowCountBinding,
                                in: LayoutSettings.minimumCustomRows...LayoutSettings.maximumCustomRows
                            )
                            .frame(width: 86)
                            .disabled(!launcherModel.layoutSettings.usesCustomGrid)
                        }
                    }

                    SettingsDivider()

                    SettingsRow(title: "整理空位", subtitle: "根据当前行列布局，将 App 向前整理以填补空位。") {
                        Button("重新整理") {
                            launcherModel.compactLayout()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            SettingsSection {
                SettingsCard {
                    SettingsRow(title: "全屏模式", subtitle: "启用后将覆盖程序坞区域显示。") {
                        Toggle("", isOn: $settingsStore.settings.isFullScreenModeEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }

            SettingsSection(title: "背景") {
                SettingsCard {
                    SettingsRow(title: "类型") {
                        Picker("", selection: $settingsStore.settings.backgroundStyle) {
                            ForEach(LauncherBackgroundStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    SettingsDivider()

                    if settingsStore.settings.backgroundStyle == .systemWallpaper {
                        SettingsRow(title: "模糊壁纸") {
                            Toggle("", isOn: $settingsStore.settings.isWallpaperBlurred)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    } else {
                        SettingsRow(title: "玻璃材质") {
                            GlassMaterialStrengthSlider(value: glassMaterialStrengthBinding)
                                .frame(width: 360, height: 36)
                        }
                    }
                }
            }
        }
    }

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsSection(title: "高级") {
                SettingsCard {
                    SettingsRow(title: "启动台显示在") {
                        Picker("", selection: $settingsStore.settings.displayStrategy) {
                            ForEach(LauncherDisplayStrategy.allCases) { strategy in
                                Text(strategy.title).tag(strategy)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 168)
                    }

                    SettingsDivider()

                    SettingsRow(title: "回到首页") {
                        Picker("", selection: returnHomeBinding) {
                            Text("从不").tag(false)
                            Text("每次打开").tag(true)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }
            }

            SettingsSection {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("布局数据备份")
                                    .font(.title3.weight(.semibold))

                                Text("导入或导出 LaunchOS 布局，用于备份、恢复或在设备之间迁移。")
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }

                        SettingsDivider()

                        HStack {
                            Spacer()

                            Button("导入") {
                                importBackup()
                            }
                            .buttonStyle(.bordered)

                            Button("导出") {
                                exportBackup()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }

            SettingsSection(title: "诊断") {
                SettingsCard {
                    SettingsRow(title: "日志", subtitle: launcherModel.layoutWarningMessage) {
                        Button("导出") {
                            exportDiagnostics()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if !launcherModel.hiddenApps.isEmpty {
                SettingsSection(title: "隐藏应用") {
                    SettingsCard {
                        SettingsRow(title: "恢复隐藏应用", subtitle: "\(launcherModel.hiddenApps.count) 个应用已隐藏") {
                            Button("恢复全部") {
                                launcherModel.restoreAllHiddenApps()
                            }
                            .buttonStyle(.bordered)
                        }

                        ForEach(launcherModel.hiddenApps) { app in
                            SettingsDivider()

                            HiddenAppRow(app: app, iconRefreshToken: launcherModel.iconRefreshToken) {
                                launcherModel.restoreApp(app.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var aboutContent: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 10)

            ZStack(alignment: .topTrailing) {
                Image(nsImage: launchOSAboutIcon)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                Text("Free")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.background, in: Capsule())
                    .overlay {
                        Capsule().stroke(.primary.opacity(0.7), lineWidth: 1)
                    }
                    .offset(x: 10, y: -8)
            }

            VStack(spacing: 8) {
                Text("LaunchOS")
                    .font(.system(size: 40, weight: .bold))

                Text(versionText)
                    .font(.title3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }

            SettingsCard {
                AboutLinkRow(title: "官网", value: "launchosapp.com", url: "https://launchosapp.com")
                SettingsDivider()
                AboutLinkRow(title: "X/Twitter", value: "@RemixDesignHQ", url: "https://x.com/RemixDesignHQ")
                SettingsDivider()
                AboutLinkRow(title: "小红书", value: "@launchos", url: "https://www.xiaohongshu.com")
            }
            .padding(.horizontal, 8)

            HStack(spacing: 16) {
                Link("隐私协议", destination: URL(string: "https://launchosapp.com/privacy")!)
                Link("使用条款", destination: URL(string: "https://launchosapp.com/terms")!)
            }
            .font(.title3.weight(.semibold))

            Text("© LaunchOS 2026 All Rights Reserved.")
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Spacer()

                Button("更新") {
                    openURL("https://launchosapp.com")
                }
                .buttonStyle(.bordered)

                Button("反馈") {
                    openURL("mailto:feedback@launchosapp.com")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }

    private var browsingModeBinding: Binding<LayoutSettings.BrowsingMode> {
        Binding {
            launcherModel.layoutSettings.browsingMode
        } set: { mode in
            launcherModel.updateBrowsingMode(mode)
        }
    }

    private var returnHomeBinding: Binding<Bool> {
        Binding {
            !launcherModel.layoutSettings.remembersLastPage
        } set: { returnsHome in
            launcherModel.updateRemembersLastPage(!returnsHome)
        }
    }

    private var customGridEnabledBinding: Binding<Bool> {
        Binding {
            launcherModel.layoutSettings.usesCustomGrid
        } set: { isEnabled in
            launcherModel.updateCustomGridEnabled(isEnabled)
        }
    }

    private var customColumnCountBinding: Binding<Int> {
        Binding {
            launcherModel.layoutSettings.customColumnCount
        } set: { columnCount in
            launcherModel.updateCustomColumnCount(columnCount)
        }
    }

    private var customRowCountBinding: Binding<Int> {
        Binding {
            launcherModel.layoutSettings.customRowCount
        } set: { rowCount in
            launcherModel.updateCustomRowCount(rowCount)
        }
    }

    private var glassMaterialStrengthBinding: Binding<Double> {
        Binding {
            settingsStore.settings.glassMaterialStrength
        } set: { strength in
            settingsStore.settings.glassMaterialStrength = min(1, max(0, strength))
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version)(\(build))"
    }

    private var launchOSAboutIcon: NSImage {
        NSImage(named: "LaunchOSAboutIcon")
            ?? NSImage(named: "AppIcon")
            ?? NSApplication.shared.applicationIconImage
    }

    @MainActor
    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "LaunchOS Backup.json"
        panel.prompt = "导出"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task {
            await launcherModel.exportLayoutBackup(to: url)
        }
    }

    @MainActor
    private func importBackup() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "导入"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task {
            await launcherModel.importLayoutBackup(from: url)
        }
    }

    @MainActor
    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "LaunchOS Diagnostics.txt"
        panel.prompt = "导出"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task {
            await launcherModel.exportDiagnostics(to: url)
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case interface
    case advanced
    case about

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general:
            "通用"
        case .interface:
            "界面"
        case .advanced:
            "高级"
        case .about:
            "关于"
        }
    }

    var iconName: String {
        switch self {
        case .general:
            "gearshape"
        case .interface:
            "command"
        case .advanced:
            "slider.horizontal.3"
        case .about:
            "info.circle"
        }
    }
}

private struct SettingsTabBar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        HStack(spacing: 14) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 31, weight: .medium))

                        Text(tab.title)
                            .font(.title2.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.title2.weight(.bold))
                    .padding(.leading, 20)
            }

            content()
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 16)

            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 20)
            .padding(.trailing, 20)
    }
}

private struct KeyCap: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .monospaced()
            .frame(minWidth: 92)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.background, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.secondary.opacity(0.18), lineWidth: 1)
            }
    }
}

private struct StatusBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

private struct GlassMaterialStrengthSlider: View {
    @Binding var value: Double
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let progress = min(1, max(0, value))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: 8)

                Capsule()
                    .fill(Color.accentColor.opacity(0.88))
                    .frame(width: width * progress, height: 8)

                HStack {
                    ForEach(0..<5, id: \.self) { index in
                        Circle()
                            .fill(Color.white.opacity(0.74))
                            .frame(width: 4, height: 4)

                        if index < 4 {
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 18)
                .allowsHitTesting(false)

                Circle()
                    .fill(.white)
                    .frame(width: isDragging ? 32 : 28, height: isDragging ? 32 : 28)
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    }
                    .offset(x: max(0, min(width - 28, width * progress - 14)))
                    .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.82), value: isDragging)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        value = min(1, max(0, gesture.location.x / width))
                    }
                    .onEnded { gesture in
                        value = min(1, max(0, gesture.location.x / width))
                        isDragging = false
                    }
            )
        }
        .accessibilityLabel("玻璃材质")
        .accessibilityValue("\(Int(value * 100))%")
    }
}

private struct AboutLinkRow: View {
    let title: String
    let value: String
    let url: String

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))

            Spacer()

            Link(value, destination: URL(string: url)!)
                .font(.title3.weight(.semibold))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct HiddenAppRow: View {
    let app: AppRecord
    let iconRefreshToken: UUID
    let restore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(app: app, size: 24, refreshToken: iconRefreshToken)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.alias ?? app.displayName)
                    .lineLimit(1)

                if let alias = app.alias, alias != app.displayName {
                    Text(app.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("恢复", action: restore)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
