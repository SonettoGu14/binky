import SwiftUI
import AppKit
import UserNotifications

// MARK: - In-window navigation (contextual links between preference tabs)

private enum OpenPreferencesRelatedTabKey: EnvironmentKey {
    static let defaultValue: (PreferencesTab) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Switch the Settings window to another tab (used for small “see also” links).
    fileprivate var openPreferencesRelatedTab: (PreferencesTab) -> Void {
        get { self[OpenPreferencesRelatedTabKey.self] }
        set { self[OpenPreferencesRelatedTabKey.self] = newValue }
    }
}

/// Small accent link, same spirit as ``SidebarView``’s “Change folder or naming…” / preset rows.
private struct PreferencesRelatedTabLink: View {
    @Environment(\.openPreferencesRelatedTab) private var openTab
    let title: String
    let tab: PreferencesTab

    var body: some View {
        Button(title) { openTab(tab) }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
    }
}

/// Tabs in the Settings window — deep-link by calling ``stagePendingTab(_:)`` right before a ``SettingsLink`` activates.
enum PreferencesTab: Int, CaseIterable, Hashable {
    case general = 0
    case destinations = 1
    case watch = 2
    case profiles = 3
    case shortcuts = 4
    case appearance = 5

    static let pendingTabUserDefaultsKey = "prefs.pendingTab"

    /// Stores the tab for the next Settings presentation and updates an already-open Settings window.
    /// Call from a gesture on the same control as ``SettingsLink`` (SwiftUI warns on `openSettings()` for this flow).
    static func stagePendingTab(_ tab: PreferencesTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: pendingTabUserDefaultsKey)
        NotificationCenter.default.post(name: .binkySelectPreferencesTab, object: tab.rawValue)
    }

    fileprivate static func consumePendingSelection() -> PreferencesTab? {
        guard UserDefaults.standard.object(forKey: pendingTabUserDefaultsKey) != nil else { return nil }
        let raw = UserDefaults.standard.integer(forKey: pendingTabUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: pendingTabUserDefaultsKey)
        return PreferencesTab(rawValue: raw)
    }
}

struct PreferencesView: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @EnvironmentObject var updater: UpdateChecker
    @State private var selectedTab: PreferencesTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem { Label(String(localized: "General", comment: "Settings UI."), systemImage: "gearshape") }
                .tag(PreferencesTab.general)
                .environmentObject(prefs)
                .environmentObject(updater)
            DestinationsTab()
                .tabItem { Label(String(localized: "Destinations", comment: "Settings UI."), systemImage: "folder") }
                .tag(PreferencesTab.destinations)
                .environmentObject(prefs)
            WatchFoldersTab()
                .tabItem { Label(String(localized: "Watch", comment: "Settings UI."), systemImage: "eye") }
                .tag(PreferencesTab.watch)
                .environmentObject(prefs)
            ProfilesOrganizerTab()
                .tabItem { Label(String(localized: "Profiles", comment: "Settings UI."), systemImage: "person.crop.circle") }
                .tag(PreferencesTab.profiles)
                .environmentObject(prefs)
            ShortcutsTab()
                .tabItem { Label(String(localized: "Shortcuts", comment: "Settings UI."), systemImage: "keyboard") }
                .tag(PreferencesTab.shortcuts)
                .environmentObject(prefs)
            AppearanceTab()
                .tabItem { Label(String(localized: "Appearance", comment: "Settings UI."), systemImage: "sidebar.left") }
                .tag(PreferencesTab.appearance)
                .environmentObject(prefs)
        }
        .environment(\.openPreferencesRelatedTab, { selectedTab = $0 })
        .frame(width: 480, height: 520)
        .onAppear {
            if let tab = PreferencesTab.consumePendingSelection() {
                selectedTab = tab
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .binkySelectPreferencesTab)) { note in
            guard let raw = note.object as? Int, let tab = PreferencesTab(rawValue: raw) else { return }
            selectedTab = tab
            UserDefaults.standard.removeObject(forKey: PreferencesTab.pendingTabUserDefaultsKey)
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @EnvironmentObject var updater: UpdateChecker
    @State private var confirmResetLifetime = false
    // Mirror the live `SMAppService.mainApp` status so the toggle stays in sync if the user changes it
    // from System Settings → General → Login Items while Binky is open.
    @State private var launchAtLoginEnabled: Bool = LaunchAtLoginManager.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Open Binky at login", comment: "Settings UI."), isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { newValue in
                        LaunchAtLoginManager.setEnabled(newValue)
                        launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
                    }
                ))
                if LaunchAtLoginManager.requiresApproval {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(String(localized: "Approve Binky in System Settings → General → Login Items.", comment: "Settings UI."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "Open…", comment: "Settings UI.")) { LaunchAtLoginManager.openLoginItemsSettings() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Toggle(String(localized: "Assign Finder tags when sorting", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.assignFinderTagsOnSortEnabled },
                    set: { prefs.assignFinderTagsOnSortEnabled = $0 }
                ))
                Text(String(localized: "Adds simple Finder tags (“New”, category hints) so files remain searchable.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(String(localized: "Prepend the “New” tag", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.sortAppendNewSemanticTagEnabled },
                    set: { prefs.sortAppendNewSemanticTagEnabled = $0 }
                ))
                .disabled(!prefs.assignFinderTagsOnSortEnabled)

                Toggle(String(localized: "Show summaries after sorting", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.showBatchSummaryDialog },
                    set: { prefs.showBatchSummaryDialog = $0 }
                ))
                Text(String(localized: "Opens the move/review summary when autonomous sorting batches finish.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle(String(localized: "Developer: unlock Plus preview tiers", comment: "Settings UI."), isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "binky.plusUnlocked") },
                    set: { UserDefaults.standard.set($0, forKey: "binky.plusUnlocked") }
                ))
                Text(String(localized: "Temporary developer flag ahead of Billing — toggles entitlement stubs only.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Behavior", comment: "Settings UI."))
            }

            Section {
                Toggle(String(localized: "Play sound when done", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.playSoundEffects },
                    set: { prefs.playSoundEffects = $0 }
                ))
                Toggle(String(localized: "Notify when done", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.notifyWhenDone },
                    set: { newValue in
                        prefs.notifyWhenDone = newValue
                        if newValue { requestNotificationAuth() }
                    }
                ))
                Text(String(localized: "To receive notifications during Focus or Do Not Disturb, allow Binky in System Settings → Focus.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(String(localized: "Open inbox in Finder when done", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.openFolderWhenDone },
                    set: { prefs.openFolderWhenDone = $0 }
                ))
                Text(String(localized: "Opens your inbox folder after each sort batch completes.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Notifications", comment: "Settings UI."))
            } footer: {
                Button(String(localized: "Notification settings…", comment: "Settings UI.")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }

            // 5. Privacy & diagnostics
            Section {
                Toggle(String(localized: "Share crash diagnostics with Binky", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.crashReportingEnabled },
                    set: { newValue in
                        prefs.crashReportingEnabled = newValue
                        DiagnosticsReporter.shared.applyCrashReportingPreference()
                    }
                ))
                Text(String(localized: "When on, Apple's MetricKit can deliver anonymous crash and hang diagnostics to Binky on your Mac. Nothing leaves your device until you choose to send a report. Requires \u{201C}Share with App Developers\u{201D} in System Settings → Privacy & Security → Analytics & Improvements.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Privacy", comment: "Settings UI."))
            } footer: {
                Button(String(localized: "Open Analytics & Improvements settings…", comment: "Settings UI.")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Analytics")!)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }

            // 6. Session history (lifetime total; per-session list is in History window)
            Section {
                Button(String(localized: "Reset total saved statistics…", comment: "Settings UI.")) {
                    confirmResetLifetime = true
                }
                .disabled(prefs.lifetimeSavedBytes == 0)
                Text(String(localized: "Clears the running total shown in History. Session history is unchanged — clear that from the History window.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Session history", comment: "Settings UI."))
            }

            Section {
                PreferencesRelatedTabLink(title: String(localized: "Keyboard shortcuts…", comment: "Settings UI."), tab: .shortcuts)
                Link(S.supportEmail, destination: URL(string: "mailto:\(S.supportEmail)")!)
            } header: {
                Text(String(localized: "Support", comment: "Settings UI."))
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLoginEnabled = LaunchAtLoginManager.isEnabled }
        .confirmationDialog(
            String(localized: "Reset the running total of bytes saved across all sessions?", comment: "Settings UI."),
            isPresented: $confirmResetLifetime,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Reset", comment: "Settings UI."), role: .destructive) {
                prefs.lifetimeSavedBytes = 0
            }
            Button(String(localized: "Cancel", comment: "Settings UI."), role: .cancel) {}
        } message: {
            Text(String(localized: "This does not clear the per-session list in History.", comment: "Settings UI."))
        }
        .onReceive(NotificationCenter.default.publisher(for: .binkyPrepareQuit)) { _ in
            confirmResetLifetime = false
        }
    }

    private func requestNotificationAuth() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            case .denied:
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
            default:
                break
            }
        }
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    var body: some View {
        Form {
            Section {
                Text(String(localized: "The main window uses the inbox navigator on the left. Fine-tune sorting under Profiles and Destinations.", comment: "Appearance organizer note."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Layout", comment: "Settings UI."))
            } footer: {
                PreferencesRelatedTabLink(title: String(localized: "Open Profiles…", comment: "Settings UI."), tab: .profiles)
            }

            Section {
                Toggle(String(localized: "Reduce motion", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.reduceMotion },
                    set: { prefs.reduceMotion = $0 }
                ))
                Text(String(localized: "Reduces expressive animation in the main window.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Accessibility", comment: "Settings UI."))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Destinations (inbox layout)

private struct DestinationsTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    var body: some View {
        Form {
            Section {
                Text(String(localized: "Sorted files stay inside your inbox folder using starter buckets:", comment: "Destinations intro."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    [
                        FileSortCategory.images.downloadsSubfolder,
                        FileSortCategory.documents.downloadsSubfolder,
                        FileSortCategory.archives.downloadsSubfolder,
                        FileSortCategory.apps.downloadsSubfolder,
                        "Media",
                        FileSortCategory.screenshots.downloadsSubfolder,
                        FileSortCategory.misc.downloadsSubfolder,
                        FileSortCategory.review.downloadsSubfolder,
                    ].joined(separator: ", ")
                )
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                Button(String(localized: "Reveal inbox in Finder", comment: "")) {
                    let path = prefs.downloadsSortRootDirectory().path
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            } header: {
                Text(String(localized: "Destination folders", comment: ""))
            } footer: {
                Text(String(localized: "Custom routing rules and multiple inbox roots are planned for Binky Plus.", comment: ""))
                    .font(.caption)
            }

            Section {
                Text(String(localized: "When a moved file already exists, Binky picks the next free name (same as Finder).", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(S.duplicateNamingPickerAccessibilityLabel, selection: Binding(
                    get: { prefs.collisionNamingStyle },
                    set: { prefs.collisionNamingStyle = $0 }
                )) {
                    ForEach(CollisionNamingStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if prefs.collisionNamingStyle == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(S.duplicateNamingCustomFieldLabel)
                                .foregroundStyle(.secondary)
                            TextField(
                                S.duplicateNamingCustomPlaceholder,
                                text: Binding(
                                    get: { prefs.collisionCustomPattern },
                                    set: { prefs.collisionCustomPattern = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 160)
                            .accessibilityLabel(S.duplicateNamingCustomFieldLabel)
                        }
                        Text(S.duplicateNamingCustomHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(String(localized: "Name collisions", comment: ""))
            } footer: {
                Text(S.duplicateNamingSectionFooter)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Profiles (organizer)

private struct ProfilesOrganizerTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    var body: some View {
        Form {
            Section {
                Text(String(localized: "Starter profile", comment: "Settings Profiles tab."))
                    .font(.headline)
                Text(String(localized: "Binky moves files into Images, Documents, Media, Archives, Apps, Screenshots, Misc, and Review under your inbox.", comment: "Profiles tab body."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !prefs.savedPresets.isEmpty {
                Section(String(localized: "Saved profiles", comment: "Settings Profiles list header.")) {
                    ForEach(prefs.savedPresets) { preset in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.name)
                                .font(.body.weight(.medium))
                            Text(preset.watchFolderEnabled
                                 ? String(localized: "Per-profile watch folder enabled", comment: "")
                                 : String(localized: "Uses global inbox watch settings", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section {
                Text(String(localized: "Multiple profiles and deeper customization ship with Binky Plus.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Watch Folders

private struct WatchFoldersTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Watch a folder", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.folderWatchEnabled },
                    set: { prefs.folderWatchEnabled = $0 }
                ))
                if prefs.folderWatchEnabled {
                    HStack {
                        Text(prefs.watchedFolderPath.isEmpty
                             ? String(localized: "No folder selected", comment: "Settings UI.")
                             : URL(fileURLWithPath: prefs.watchedFolderPath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose…", comment: "Settings UI.")) { pickGlobalWatchFolder() }
                            .buttonStyle(.bordered)
                    }
                    Text(String(localized: "The global folder uses whatever settings are in the main window (sidebar). Presets can add separate watched folders in their own settings.", comment: "Settings UI."))
                    .font(.caption)
                        .foregroundStyle(.secondary)

                    PreferencesRelatedTabLink(title: String(localized: "Sidebar sections in Appearance…", comment: "Settings UI."), tab: .appearance)
                }
            } header: {
                Text(String(localized: "Global", comment: "Settings UI."))
            }

            Section {
                if prefs.savedPresets.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "No profiles yet. Create one under Profiles to attach another watched folder (Plus preview).", comment: "Settings UI."))
                    .foregroundStyle(.secondary)
                        PreferencesRelatedTabLink(title: String(localized: "Open Profiles…", comment: "Settings UI."), tab: .profiles)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } else {
                    ForEach(prefs.savedPresets) { preset in
                        WatchFolderPresetRow(preset: preset)
                            .environmentObject(prefs)
                    }
                }
            } header: {
                Text(String(localized: "Profiles", comment: "Settings UI."))
            }
        }
        .formStyle(.grouped)
    }

    private func pickGlobalWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Watch", comment: "Open panel: choose folder to watch.")
        if panel.runModal() == .OK, let url = panel.url {
            prefs.watchedFolderPath = url.path
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                prefs.watchedFolderBookmark = bookmark
            }
        }
    }
}

private struct WatchFolderPresetRow: View {
    @EnvironmentObject var prefs: BinkyPreferences
    let preset: CompressionPreset

    private var live: CompressionPreset {
        prefs.savedPresets.first(where: { $0.id == preset.id }) ?? preset
    }

    var body: some View {
        Toggle(live.name, isOn: enabledBinding)
        if live.watchFolderEnabled {
            HStack {
                Image(systemName: "folder")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text(resolvedFolderLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, 20)
        }
    }

    private var resolvedFolderLabel: String {
        if live.watchFolderModeRaw == "unique" {
            return live.watchFolderPath.isEmpty
                ? String(localized: "No folder set — configure in Profiles", comment: "Watch row hint.")
                : URL(fileURLWithPath: live.watchFolderPath).lastPathComponent
        }
        if !prefs.watchedFolderPath.isEmpty {
            let folder = URL(fileURLWithPath: prefs.watchedFolderPath).lastPathComponent
            return String(localized: "Global (\(folder))", comment: "Watch row: uses global folder; argument is folder name.")
        }
        return String(localized: "Global watch — choose folder in Watch tab", comment: "Watch row hint.")
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { live.watchFolderEnabled },
            set: { newValue in
                guard let idx = prefs.savedPresets.firstIndex(where: { $0.id == preset.id }) else { return }
                var list = prefs.savedPresets
                list[idx].watchFolderEnabled = newValue
                prefs.savedPresets = list
            }
        )
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    @State private var shortcutErrors: [ShortcutAction: String] = [:]
    @State private var recordingAction: ShortcutAction?

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.settingsListedActions) { action in
                    shortcutRow(for: action)
                }
                HStack {
                    Spacer()
                    Button(S.shortcutsResetAll) {
                        prefs.resetAllShortcuts()
                        shortcutErrors = [:]
                        recordingAction = nil
                    }
                    .disabled(ShortcutAction.settingsListedActions.allSatisfy { prefs.isDefaultShortcut($0) })
                }
            } header: {
                Text(S.shortcutsCustomizableHeader)
            } footer: {
                Text(S.shortcutsTabServicesFooter)
                    .font(.caption)
            }

            Section {
                ForEach(S.fixedMenuShortcutReference) { row in
                    HStack(spacing: 12) {
                        Text(row.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 12)
                        KeyComboView(combo: row.keys)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.title), \(row.keys)")
                }
            } header: {
                Text(S.shortcutsFixedHeader)
            }

            Section {
                Text(S.shortcutsAppDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Shortcuts app", comment: "Settings UI."))
            }

            Section {
                Text(S.shortcutsTabHelpFooter(helpMenuShortcut: BinkyFixedShortcut.binkyHelp.shortcut.displayString))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "More help", comment: "Settings UI."))
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func shortcutRow(for action: ShortcutAction) -> some View {
        let s = prefs.shortcut(for: action)
        let sysWarn = ShortcutValidator.systemWarning(for: s)
        let isRecording = recordingAction == action
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(action.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    ShortcutRecorderField(
                        prefs: prefs,
                        action: action,
                        isRecording: recordingBinding(for: action),
                        inlineError: errorBinding(for: action)
                    )
                    .frame(minWidth: 128, maxWidth: 160)
                    if let w = sysWarn, !isRecording {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help("\(S.shortcutsSystemWarningPrefix) \(w)")
                            .accessibilityLabel("\(S.shortcutsSystemWarningPrefix) \(w)")
                    }
                    if isRecording {
                        Button(S.shortcutsCancelEdit) {
                            recordingAction = nil
                            shortcutErrors.removeValue(forKey: action)
                        }
                        .fixedSize()
                    } else {
                        Button(S.shortcutsEdit) {
                            shortcutErrors.removeValue(forKey: action)
                            recordingAction = action
                        }
                        .fixedSize()
                        if !prefs.isDefaultShortcut(action) {
                            Button(S.shortcutsResetRow) {
                                prefs.resetShortcut(action)
                                shortcutErrors.removeValue(forKey: action)
                            }
                            .fixedSize()
                        }
                    }
                }
            }
            if isRecording {
                Text(S.shortcutsRecorderHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let err = shortcutErrors[action] {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: action, shortcut: s, systemWarn: sysWarn, isRecording: isRecording))
    }

    private func accessibilityLabel(for action: ShortcutAction, shortcut: CustomShortcut, systemWarn: String?, isRecording: Bool) -> String {
        var parts = "\(action.title), \(shortcut.displayString)"
        if isRecording { parts += ", recording — \(S.shortcutsRecorderHint)" }
        if let w = systemWarn, !isRecording { parts += ", \(S.shortcutsSystemWarningPrefix) \(w)" }
        if let e = shortcutErrors[action] { parts += ", \(e)" }
        return parts
    }

    private func recordingBinding(for action: ShortcutAction) -> Binding<Bool> {
        Binding(
            get: { recordingAction == action },
            set: { newValue in
                if newValue {
                    if recordingAction != action {
                        if let prev = recordingAction {
                            shortcutErrors.removeValue(forKey: prev)
                        }
                        recordingAction = action
                    }
                } else if recordingAction == action {
                    recordingAction = nil
                }
            }
        )
    }

    private func errorBinding(for action: ShortcutAction) -> Binding<String?> {
        Binding(
            get: { shortcutErrors[action] },
            set: { newVal in
                if let newVal {
                    shortcutErrors[action] = newVal
                } else {
                    shortcutErrors.removeValue(forKey: action)
                }
            }
        )
    }
}

/// Renders a compact key combo like `⌘⇧V` as individual keycaps.
private struct KeyComboView: View {
    let combo: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(combo.enumerated()), id: \.offset) { _, ch in
                KeyCapView(label: String(ch))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A single keycap, sized to its content but with a uniform minimum so modifier glyphs and letters line up.
private struct KeyCapView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}
