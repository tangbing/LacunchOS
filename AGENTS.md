# AGENTS.md

## Project Mission

Build a native macOS 26 Tahoe Launchpad replacement inspired by LaunchOS.

The product should restore the classic Launchpad workflow: a full-screen app grid, paging, folders, drag-and-drop organization, fast search, keyboard control, Dock/menu bar access, global shortcuts, and later F4, trackpad gestures, hot corners, layout import, backup, and Pro-only advanced features.

Primary requirements live in:

- `docs/launchos-requirements.md`

Every implementation decision should map back to that PRD unless the user explicitly changes scope.

## Platform And Technology

- Target platform: macOS 26 Tahoe.
- Primary UI framework: SwiftUI.
- Use AppKit where SwiftUI cannot provide the required macOS-level behavior cleanly.
- Preferred language: Swift.
- Preferred package manager: Swift Package Manager.
- Do not build this as Electron, Tauri, a web app, or a menu-bar-only utility.
- The app should feel like a native Apple system surface, not a generic third-party launcher.

## Design Principles

- Follow Apple Human Interface Guidelines for macOS.
- Keep the first usable surface as the actual launcher, not a marketing or onboarding screen.
- Prioritize clarity, spatial memory, smooth motion, and native-feeling interactions.
- The main launcher should resemble the old Launchpad interaction model while adapting visually to macOS 26 Tahoe.
- Use SwiftUI-native controls and materials where possible.
- Use AppKit visual effects only when needed for system-level polish.
- Avoid decorative UI that does not serve the launcher workflow.
- Text must never overlap icons, controls, folders, search fields, or pagination.
- Keep compact controls compact. Do not use oversized hero-style typography inside app UI.
- Prefer system symbols and native icons over custom vector decorations.

## Dependency Policy

Use mature GitHub frameworks when they reduce risk or avoid reimplementing well-known macOS infrastructure.

Before adding a dependency, verify:

- It supports macOS.
- It supports Swift Package Manager.
- It is actively maintained or stable enough for production use.
- Its license is compatible with commercial desktop software.
- It has a narrow, understandable API surface.
- It does not force a non-native UI architecture.

Good candidate areas for third-party libraries:

- Global keyboard shortcuts.
- Login item management.
- Automatic updates.
- Settings helpers.
- Hotkey recording controls.
- Sparkle-style update delivery.

Avoid dependencies for:

- Core app grid rendering.
- Basic search ranking unless the implementation becomes genuinely complex.
- Simple JSON persistence.
- Launching apps.
- Native window coordination that is clearer with AppKit.

Potential libraries to evaluate when implementation reaches the relevant milestone:

- `sindresorhus/KeyboardShortcuts` for user-configurable global shortcuts.
- `sparkle-project/Sparkle` for app updates.
- `sindresorhus/LaunchAtLogin` for login item support.

Do not add a package casually. Record why it exists in the relevant implementation notes or code review summary.

## Architecture Guidance

Prefer a small, testable native architecture:

- SwiftUI views own presentation and local view state.
- Models are simple `Codable`, `Identifiable`, and `Hashable` value types where possible.
- Shared app state should use Swift Observation where available.
- AppKit bridge objects should be isolated behind coordinators or services.
- Long-lived system integrations should not be hidden inside SwiftUI view bodies.

Suggested module responsibilities:

- `AppScanner`: scans system and user Applications directories.
- `AppLauncher`: opens selected `.app` bundles.
- `LayoutStore`: persists app order, folders, aliases, hidden state, and layout settings.
- `SearchService`: ranks app results by display name, default name, alias, abbreviation, and pinyin when available.
- `LauncherWindowCoordinator`: owns full-screen launcher presentation and closing behavior.
- `MenuBarController`: owns menu bar item and menu actions.
- `HotkeyService`: owns global shortcut registration.
- `SettingsStore`: owns user preferences.
- `DisplayService`: resolves main display, active display, and pointer display behavior.

Keep SwiftUI views small:

- Split large screens into focused subviews.
- Avoid putting file scanning, app launching, persistence, or event monitoring directly in view bodies.
- Avoid side effects in computed `some View` properties.
- Prefer explicit dependency injection for services that need to be mocked or tested.

## MVP Implementation Order

Implement the product in working vertical slices. After each slice, the app must build and launch.

### Milestone 1: Native App Shell

- Create a macOS SwiftUI app project.
- Add Dock and/or menu bar entry.
- Present a full-screen launcher window.
- Close with `Esc` and blank-area click.

### Milestone 2: App Discovery And Launch

- Scan `/Applications`.
- Scan `~/Applications`.
- Deduplicate discovered apps.
- Display apps in a responsive grid.
- Launch apps on click.

### Milestone 3: Search And Keyboard

- Auto-focus search when launcher opens.
- Implement realtime search.
- Open top result with Enter.
- Add arrow-key navigation.
- Add `Command + Left` and `Command + Right` paging.

### Milestone 4: Paging And Layout Persistence

- Implement horizontal paged browsing.
- Persist page, app order, and layout.
- Remember last position or return home based on setting.

### Milestone 5: Organization

- Add drag sorting.
- Add folder creation by drag.
- Add folder open, close, and rename.
- Add basic right-click menus.

### Milestone 6: System-Level Features

- Add user-configurable global shortcut.
- Add F4 support if feasible.
- Add hot corners.
- Add multi-display strategy.
- Evaluate trackpad gesture implementation carefully.

### Milestone 7: Advanced Features

- Custom grid rows and columns.
- Hidden apps.
- Custom app sources.
- Layout backup and restore.
- Native Launchpad layout import.
- Update system.
- Trial / Pro gating if requested.

## Build And Verification Requirements

Every code change must leave the project runnable.

After creating the Xcode project:

- Run a clean build after meaningful edits.
- Prefer non-interactive build commands.
- Use the project scheme documented in the repo.
- If a command fails because of sandboxing or missing permissions, request approval instead of skipping verification.

Expected verification pattern once the project exists:

```sh
xcodebuild -project <ProjectName>.xcodeproj -scheme <SchemeName> -destination 'platform=macOS' build
```

If the project uses Swift Package Manager only:

```sh
swift build
swift test
```

Before declaring work complete:

- Confirm the app builds without compile errors.
- Run available tests.
- Manually sanity-check launch, search, grid display, and app opening when the changed area affects them.
- Report any verification that could not be run and why.

## Runtime Quality Bar

The launcher must remain responsive:

- Opening the launcher should feel immediate.
- Searching should update without visible typing lag.
- Paging and dragging should not stutter under normal app counts.
- Background scanning should not freeze the UI.
- Use async work for scanning and expensive refreshes.
- Cache app metadata and icons where appropriate.

## macOS Integration Rules

- Use `NSWorkspace` for app discovery and launching where appropriate.
- Use AppKit for menu bar, low-level windows, event monitors, hot corners, and display coordination when SwiftUI is insufficient.
- Keep permission-sensitive features explicit and explainable.
- Do not request unnecessary Accessibility, Input Monitoring, or Automation permissions.
- Avoid private APIs unless the user explicitly accepts the risk.
- For macOS 26-specific APIs, use availability checks if the project must still compile on earlier SDKs.

## Data Persistence

Prefer simple, inspectable persistence:

- Use `Application Support` for layout data and backups.
- Use `UserDefaults` only for small preferences.
- Use `Codable` JSON for app layout, folders, aliases, hidden apps, and custom sources unless requirements outgrow it.
- Never overwrite the current layout during import or restore without a recoverable backup.

Suggested persisted data:

- App identity and resolved path.
- Display name and optional alias.
- Page order.
- Folder membership.
- Hidden state.
- Last opened date.
- Layout settings.
- Browsing mode.
- Display strategy.
- Custom app sources.

## Search Requirements

Initial search should support:

- Case-insensitive substring matching.
- App display name.
- Bundle name.
- Alias/custom name.
- Simple abbreviation matching.

Future search should support:

- CamelCase matching.
- English initial-letter matching.
- Full pinyin matching.
- Pinyin initial-letter matching.
- Ranking by match quality.

Keep search deterministic and testable.

## Accessibility And Keyboard

Core launcher flows must be usable from the keyboard:

- Arrow keys move focus.
- Enter opens the highlighted app or folder.
- Esc closes or cancels based on context.
- `Command + ,` opens settings.
- `Command + Q` quits the app.
- `Command + Left` and `Command + Right` switch pages.

Make focus state visible and stable.

## Safety Rules

- Do not implement credential extraction, password dumping, or unrelated system inspection features.
- Do not delete apps or related files until the clean uninstall feature is intentionally scoped.
- Clean uninstall must show the delete list and require user confirmation.
- Do not delete user data that cannot be confidently attributed to the selected app.
- Do not use destructive shell commands during development unless the user explicitly requests them.

## Coding Standards

- Match the existing project style once code exists.
- Keep comments short and useful.
- Prefer native Swift types and APIs.
- Keep files focused.
- Add tests for ranking, persistence, scanning filters, and layout transformations.
- Avoid broad refactors while implementing a single feature.
- Do not leave placeholder UI for features that appear enabled.

## Done Definition

A task is done only when:

- The requested behavior is implemented.
- The app builds successfully.
- Relevant tests pass or the reason they could not run is documented.
- The changed UI follows native macOS conventions.
- The implementation does not regress existing flows.
- Any new dependency has a clear purpose.
- The final response summarizes what changed and how it was verified.
