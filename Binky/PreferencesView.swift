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
                .tabItem { Label(String(localized: "Output", comment: "Settings UI."), systemImage: "folder") }
                .tag(PreferencesTab.destinations)
                .environmentObject(prefs)
            WatchFoldersTab()
                .tabItem { Label(String(localized: "Watch Folder", comment: "Settings UI."), systemImage: "eye") }
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
        .frame(width: 540, height: 640)
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

                Toggle(String(localized: "Open watch folder in Finder when done", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.openFolderWhenDone },
                    set: { prefs.openFolderWhenDone = $0 }
                ))
                Text(String(localized: "Opens your watch folder in Finder after each sort batch completes.", comment: "Settings UI."))
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
                Text(String(localized: "Choose how much detail the organizer sidebar shows.", comment: "Appearance: organizer sidebar detail level intro."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(String(localized: "Sidebar style", comment: "Settings UI."), selection: Binding(
                    get: { prefs.sidebarSimpleMode },
                    set: { prefs.applySidebarSimpleMode($0) }
                )) {
                    Text(String(localized: "Focused", comment: "Settings UI: organizer sidebar style (minimal).")).tag(true)
                    Text(String(localized: "Expanded", comment: "Settings UI: organizer sidebar style (detailed).")).tag(false)
                }
                .pickerStyle(.radioGroup)

                if !prefs.sidebarSimpleMode {
                    Text(String(localized: "Expanded keeps profile selection, watch-folder controls, and quick settings visible at once.", comment: "Settings UI: organizer expanded sidebar summary."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(localized: "Focused keeps the sidebar calmer and trims extra detail until you need it.", comment: "Settings UI: organizer focused sidebar summary."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(String(localized: "Layout", comment: "Settings UI."))
            } footer: {
                PreferencesRelatedTabLink(title: String(localized: "Open Profiles…", comment: "Settings UI."), tab: .profiles)
            }

            Section {
                Toggle(String(localized: "Show menu bar icon", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.showMenuBarIcon },
                    set: { newVal in
                        if !newVal, prefs.menuBarOnlyMode {
                            return
                        }
                        prefs.showMenuBarIcon = newVal
                        BinkyMenuBarController.shared.refresh()
                    }
                ))
                .disabled(prefs.menuBarOnlyMode)
                Toggle(String(localized: "Menu bar only (hide Dock icon)", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.menuBarOnlyMode },
                    set: { newVal in
                        prefs.menuBarOnlyMode = newVal
                        if newVal {
                            prefs.showMenuBarIcon = true
                        }
                        BinkyActivationPolicy.apply(menuBarOnly: newVal)
                        BinkyMenuBarController.shared.refresh()
                    }
                ))
                Text(String(localized: "Keeps Downloads sorting awake even when the window is closed. Use the menu bar for Sort Now and History.", comment: "Settings UI: menu bar mode hint."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if prefs.menuBarOnlyMode {
                    Text(String(localized: "Menu bar icon stays on — it’s how you reach Binky without the Dock.", comment: "Settings UI: menu bar only constraint."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(String(localized: "Menu bar", comment: "Settings UI."))
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
        .onAppear {
            BinkyActivationPolicy.apply(menuBarOnly: prefs.menuBarOnlyMode)
            BinkyMenuBarController.shared.refresh()
        }
    }
}

// MARK: - Destinations (inbox layout)

private struct DestinationsTab: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @State private var showingPreview = false
    @State private var previewRows: [SortPreviewEntry] = []

    private var excludeFragmentsBinding: Binding<String> {
        Binding(
            get: { prefs.sortExcludeNameFragments.joined(separator: "\n") },
            set: { newVal in
                prefs.sortExcludeNameFragments = newVal
                    .split(whereSeparator: \.isNewline)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Text(String(localized: "This tab controls where sorted files are placed inside your watch folder:", comment: "Destinations intro."))
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
                Button(String(localized: "Reveal output root in Finder", comment: "")) {
                    let path = prefs.downloadsSortRootDirectory().path
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            } header: {
                Text(String(localized: "Output folders", comment: ""))
            } footer: {
                Text(String(localized: "Turn off custom routing to use only these automatic buckets. Profiles can still watch extra folders.", comment: "Output folders footer."))
                    .font(.caption)
            }

            Section {
                Toggle(String(localized: "Custom routing rules", comment: "Output settings."), isOn: $prefs.sortCustomRulesEnabled)
                if prefs.sortCustomRulesEnabled {
                    Text(String(localized: "Rules run top to bottom — the first match wins. If nothing matches, Binky uses automatic buckets.", comment: "Routing hint."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SortRulesListEditor(rules: Binding(
                        get: { prefs.sortRoutingRules },
                        set: { prefs.sortRoutingRules = $0 }
                    ))
                        .frame(minHeight: 200)
                }
            } header: {
                Text(String(localized: "Routing", comment: "Output settings."))
            }

            Section {
                TextField(String(localized: "Ignored extensions (comma-separated)", comment: "Output settings."), text: $prefs.sortExcludeExtensionsCSV)
                    .textFieldStyle(.roundedBorder)
                Text(String(localized: "Example: iso, sparsebundle", comment: "Output settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Ignored filename fragments — one per line", comment: "Output settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: excludeFragmentsBinding)
                    .frame(minHeight: 72)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text(String(localized: "Never sort", comment: "Output settings."))
            }

            Section {
                Button(String(localized: "Preview sort…", comment: "Output settings.")) {
                    previewRows = DownloadsSortOrchestrator.shared.previewInbox(prefs: prefs)
                    showingPreview = true
                }
                Text(String(localized: "Shows where top-level inbox files would land. Nothing moves until you sort.", comment: "Output settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Dry run", comment: "Output settings."))
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
        .sheet(isPresented: $showingPreview) {
            SortPreviewSheet(rows: previewRows)
        }
    }
}

private struct SortRulesListEditor: View {
    @Binding var rules: [InboxSortRule]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, _ in
                    SortRuleEditor(rules: $rules, ruleIndex: index)
                }
                .onMove { source, destination in
                    rules.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    rules.remove(atOffsets: offsets)
                }
            }
            .frame(minHeight: 160)
            HStack {
                Button(String(localized: "Add rule", comment: "Routing rules.")) {
                    rules.append(InboxSortRule.fresh(order: rules.count + 1))
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
    }
}

private struct SortRuleEditor: View {
    @Binding var rules: [InboxSortRule]
    let ruleIndex: Int

    private var noDateAddedPredicateKind: SortDateAddedPredicateKind {
        SortDateAddedPredicateKind(rawValue: "none") ?? .olderThanDays
    }

    private func binding<T>(_ keyPath: WritableKeyPath<InboxSortRule, T>) -> Binding<T> {
        Binding(
            get: { rules[ruleIndex][keyPath: keyPath] },
            set: { newVal in
                var copy = rules
                copy[ruleIndex][keyPath: keyPath] = newVal
                rules = copy
            }
        )
    }

    private var extensionsBinding: Binding<String> {
        Binding(
            get: { rules[ruleIndex].matchExtensions.joined(separator: ", ") },
            set: { newVal in
                var copy = rules
                let parts = newVal.split(separator: ",").map { chunk in
                    String(chunk).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        .replacingOccurrences(of: ".", with: "")
                }.filter { !$0.isEmpty }
                copy[ruleIndex].matchExtensions = parts
                rules = copy
            }
        )
    }

    private var addedTagsBinding: Binding<String> {
        Binding(
            get: { rules[ruleIndex].addedTags.joined(separator: ", ") },
            set: { newVal in
                var copy = rules
                let parts = newVal.split(separator: ",").map { chunk in
                    String(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                copy[ruleIndex].addedTags = parts
                rules = copy
            }
        )
    }

    private var minSizeBinding: Binding<String> {
        Binding(
            get: {
                if let b = rules[ruleIndex].minSizeBytes { return "\(b)" }
                return ""
            },
            set: { raw in
                var copy = rules
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                copy[ruleIndex].minSizeBytes = trimmed.isEmpty ? nil : Int64(trimmed)
                rules = copy
            }
        )
    }

    private var maxSizeBinding: Binding<String> {
        Binding(
            get: {
                if let b = rules[ruleIndex].maxSizeBytes { return "\(b)" }
                return ""
            },
            set: { raw in
                var copy = rules
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                copy[ruleIndex].maxSizeBytes = trimmed.isEmpty ? nil : Int64(trimmed)
                rules = copy
            }
        )
    }

    private var dateKindBinding: Binding<SortDateAddedPredicateKind> {
        Binding(
            get: { rules[ruleIndex].dateAddedPredicate?.kind ?? noDateAddedPredicateKind },
            set: { newKind in
                var copy = rules
                if newKind == noDateAddedPredicateKind {
                    copy[ruleIndex].dateAddedPredicate = nil
                } else {
                    let days = copy[ruleIndex].dateAddedPredicate?.days ?? 7
                    copy[ruleIndex].dateAddedPredicate = SortDateAddedPredicate(kind: newKind, days: max(0, days))
                }
                rules = copy
            }
        )
    }

    private var dateDaysBinding: Binding<Int> {
        Binding(
            get: { rules[ruleIndex].dateAddedPredicate?.days ?? 7 },
            set: { newDays in
                var copy = rules
                let kind = copy[ruleIndex].dateAddedPredicate?.kind ?? SortDateAddedPredicateKind.olderThanDays
                guard kind != noDateAddedPredicateKind else { return }
                copy[ruleIndex].dateAddedPredicate = SortDateAddedPredicate(kind: kind, days: max(0, newDays))
                rules = copy
            }
        )
    }

    var body: some View {
        Group {
            if rules.indices.contains(ruleIndex) {
                DisclosureGroup {
                    Toggle(String(localized: "Enabled", comment: "Rule editor."), isOn: binding(\.isEnabled))
                    TextField(String(localized: "Rule name", comment: "Rule editor."), text: binding(\.name))
                    TextField(String(localized: "Extensions (comma-separated, empty = any)", comment: "Rule editor."), text: extensionsBinding)
                        .textFieldStyle(.roundedBorder)
                    TextField(String(localized: "Filename contains (empty = any)", comment: "Rule editor."), text: binding(\.nameContains))
                        .textFieldStyle(.roundedBorder)
                    Picker(String(localized: "Kind", comment: "Rule editor."), selection: binding(\.fileKindFilter)) {
                        ForEach(SortFileKindFilter.allCases) { filter in
                            Text(filter.localizedTitle).tag(filter)
                        }
                    }
                    HStack {
                        TextField(String(localized: "Min size (bytes)", comment: "Rule editor."), text: minSizeBinding)
                            .textFieldStyle(.roundedBorder)
                        TextField(String(localized: "Max size (bytes)", comment: "Rule editor."), text: maxSizeBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                    Picker(String(localized: "Date added", comment: "Rule editor."), selection: dateKindBinding) {
                        Text(String(localized: "Ignore", comment: "Rule editor.")).tag(noDateAddedPredicateKind)
                        Text(String(localized: "Added within last … days", comment: "Rule editor.")).tag(SortDateAddedPredicateKind.newerThanDays)
                        Text(String(localized: "Added more than … days ago", comment: "Rule editor.")).tag(SortDateAddedPredicateKind.olderThanDays)
                    }
                    if let predicate = rules[ruleIndex].dateAddedPredicate,
                       predicate.kind != noDateAddedPredicateKind {
                        Stepper(value: dateDaysBinding, in: 0...3650) {
                            Text(String.localizedStringWithFormat(String(localized: "Days: %lld", comment: "Rule editor."), Int64(dateDaysBinding.wrappedValue)))
                        }
                    }
                    TextField(String(localized: "Destination folder (under inbox)", comment: "Rule editor."), text: binding(\.destinationRelativePath))
                        .textFieldStyle(.roundedBorder)
                    Picker(String(localized: "Rename", comment: "Rule editor."), selection: binding(\.renameStyle)) {
                        ForEach(SortRenameStyle.allCases) { style in
                            Text(style.localizedTitle).tag(style)
                        }
                    }
                    if rules[ruleIndex].renameStyle == .template {
                        TextField("{date} {stem}{ext}", text: binding(\.renameTemplate))
                            .textFieldStyle(.roundedBorder)
                        Text(String(localized: "Tokens: {date}, {stem}, {ext}, {n}", comment: "Rule editor rename hint."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    TextField(String(localized: "Tags on match (comma-separated)", comment: "Rule editor."), text: addedTagsBinding)
                        .textFieldStyle(.roundedBorder)
                } label: {
                    Text(rules[ruleIndex].name)
                        .font(.body.weight(.medium))
                }
            }
        }
    }
}

// MARK: - Profiles (organizer)

private struct ProfilesOrganizerTab: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @State private var selectedPresetID: UUID?
    @State private var newCustomTagDraft: String = ""
    @State private var confirmDeleteProfile = false

    private static let newTagExpiryChoices = [0, 1, 3, 7, 14, 30]

    private var selectedPresetIndex: Int? {
        guard let id = selectedPresetID else { return nil }
        return prefs.savedPresets.firstIndex { $0.id == id }
    }

    private var canDeleteSelected: Bool {
        prefs.savedPresets.count > 1 && selectedPresetIndex != nil
    }

    var body: some View {
        Form {
            Section(String(localized: "Profiles", comment: "Settings Profiles list header.")) {
                ForEach(Array(prefs.savedPresets.enumerated()), id: \.element.id) { _, preset in
                    profileListRow(preset)
                }

                Button {
                    createNewProfile()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .frame(width: 16, alignment: .center)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Add", comment: "Profiles list: add a new profile row."))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section {
                HStack(spacing: 18) {
                    profileToolbarButton(
                        systemImage: "plus",
                        title: String(localized: "Add", comment: "Profiles toolbar: create profile.")
                    ) {
                        createNewProfile()
                    }

                    profileToolbarButton(
                        systemImage: "doc.on.doc",
                        title: String(localized: "Duplicate", comment: "Profiles toolbar: duplicate selected profile.")
                    ) {
                        duplicateSelectedProfile()
                    }
                    .disabled(selectedPresetIndex == nil)

                    profileToolbarButton(
                        systemImage: "trash",
                        title: String(localized: "Delete", comment: "Profiles toolbar: delete selected profile.")
                    ) {
                        confirmDeleteProfile = true
                    }
                    .disabled(!canDeleteSelected)

                    Spacer(minLength: 0)
                }
            }

            if let idx = selectedPresetIndex {
                Section(String(localized: "Name", comment: "Profile editor section.")) {
                    TextField(
                        String(localized: "Profile name", comment: "Profile editor: name field placeholder."),
                        text: profileNameBinding(presetIndex: idx)
                    )
                    .textFieldStyle(.roundedBorder)
                }

                Section(String(localized: "Watch folder", comment: "Profile editor section: watch folder.")) {
                    Toggle(
                        String(localized: "Use a per-profile watch folder", comment: "Profile editor: enable per-profile watch folder."),
                        isOn: watchEnabledBinding(presetIndex: idx)
                    )
                    if prefs.savedPresets[idx].watchFolderEnabled {
                        Picker(
                            String(localized: "Folder source", comment: "Profile editor: per-profile vs global watch folder source."),
                            selection: watchModeBinding(presetIndex: idx)
                        ) {
                            Text(String(localized: "Use global watch folder", comment: "Profile editor: global watch source.")).tag("global")
                            Text(String(localized: "Use a unique folder", comment: "Profile editor: unique watch source.")).tag("unique")
                        }
                        .pickerStyle(.radioGroup)

                        if prefs.savedPresets[idx].watchFolderModeRaw == "unique" {
                            HStack {
                                Text(prefs.savedPresets[idx].watchFolderPath.isEmpty
                                     ? String(localized: "No folder selected", comment: "Profile editor: no per-profile watch folder.")
                                     : URL(fileURLWithPath: prefs.savedPresets[idx].watchFolderPath).lastPathComponent)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button(String(localized: "Choose…", comment: "Profile editor: pick per-profile watch folder.")) {
                                    pickWatchFolder(presetIndex: idx)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } else {
                        Text(String(localized: "This profile uses the global watch folder settings.", comment: "Profile editor: watch off helper."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section(String(localized: "Custom tags", comment: "Profile editor section: custom Finder tags.")) {
                    if prefs.savedPresets[idx].customFinderTags.isEmpty {
                        Text(String(localized: "No custom tags. Sorted files only get Binky's category tags.", comment: "Profile editor: no custom tags."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(prefs.savedPresets[idx].customFinderTags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                            Spacer()
                            Button(String(localized: "Remove", comment: "Profile editor: remove custom Finder tag.")) {
                                removeCustomTag(tag, presetIndex: idx)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        TextField(
                            String(localized: "Tag name", comment: "Profile editor: add custom Finder tag placeholder."),
                            text: $newCustomTagDraft
                        )
                        .textFieldStyle(.roundedBorder)
                        Button(String(localized: "Add", comment: "Profile editor: add custom Finder tag.")) {
                            addCustomTag(presetIndex: idx)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section(String(localized: "\u{201C}New\u{201D} tag expiry", comment: "Profile editor section: New tag expiry.")) {
                    Picker(
                        String(localized: "Expires after", comment: "Profile editor: New tag expiry picker."),
                        selection: newTagExpiryBinding(presetIndex: idx)
                    ) {
                        ForEach(Self.newTagExpiryChoices, id: \.self) { days in
                            Text(newTagExpiryChoiceLabel(days)).tag(days)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(String(localized: "Sort rules", comment: "Profile editor section: sort rules.")) {
                    if prefs.savedPresets[idx].inboxSortRules.isEmpty {
                        Text(String(localized: "No rules. Binky uses default buckets.", comment: "Profile editor: empty rules."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(String(localized: "When this profile has rules, they replace global custom routing for files from its watch folder.", comment: "Profile editor: rules hint."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SortRulesListEditor(rules: inboxSortRulesBinding(presetIndex: idx))
                        .frame(minHeight: 200)
                }

                Section(String(localized: "After sorting", comment: "Profile editor section: post-sort shortcut.")) {
                    TextField(
                        String(localized: "Shortcut name (e.g. \u{201C}Notify Slack\u{201D})", comment: "Profile editor: post-sort shortcut."),
                        text: postSortShortcutBinding(presetIndex: idx)
                    )
                    .textFieldStyle(.roundedBorder)
                    Text(String(localized: "Runs this Shortcut with the moved file as input.", comment: "Profile editor: shortcut hint."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            syncSelectedPresetSelection()
        }
        .onChange(of: prefs.savedPresets.map(\.id)) { _, _ in
            syncSelectedPresetSelection()
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $confirmDeleteProfile,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete", comment: "Profile editor: confirm delete."), role: .destructive) {
                deleteSelectedProfile()
            }
            Button(String(localized: "Cancel", comment: "Profile editor: cancel delete."), role: .cancel) {}
        }
    }

    private var deleteConfirmationTitle: String {
        guard let idx = selectedPresetIndex else {
            return String(localized: "Delete profile?", comment: "Profile editor: generic delete title.")
        }
        return String.localizedStringWithFormat(
            String(localized: "Delete \u{201C}%@\u{201D}?", comment: "Profile editor: delete title; argument is profile name."),
            prefs.savedPresets[idx].name
        )
    }

    @ViewBuilder
    private func profileListRow(_ preset: CompressionPreset) -> some View {
        let isSelected = preset.id == selectedPresetID
        Button {
            selectedPresetID = preset.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(profileSubtitle(preset))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(preset.name). \(profileSubtitle(preset))\(isSelected ? ", selected" : "")")
    }

    private func profileToolbarButton(
        systemImage: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private func profileSubtitle(_ preset: CompressionPreset) -> String {
        var parts: [String] = []

        if preset.watchFolderEnabled {
            if preset.watchFolderModeRaw == "unique" {
                if preset.watchFolderPath.isEmpty {
                    parts.append(String(localized: "Unique folder (not set)", comment: "Profile subtitle: unique watch folder not chosen."))
                } else {
                    parts.append(URL(fileURLWithPath: preset.watchFolderPath).lastPathComponent)
                }
            } else {
                parts.append(String(localized: "Global watch", comment: "Profile subtitle: uses global watch folder."))
            }
        } else {
            parts.append(String(localized: "Watch off", comment: "Profile subtitle: watch disabled."))
        }

        let tagCount = preset.customFinderTags.count
        if tagCount == 1 {
            parts.append(String(localized: "1 tag", comment: "Profile subtitle: single custom tag."))
        } else if tagCount > 1 {
            parts.append(String.localizedStringWithFormat(
                String(localized: "%lld tags", comment: "Profile subtitle: multiple custom tags."),
                Int64(tagCount)
            ))
        }

        let ruleCount = preset.inboxSortRules.count
        if ruleCount == 1 {
            parts.append(String(localized: "1 rule", comment: "Profile subtitle: single sort rule."))
        } else if ruleCount > 1 {
            parts.append(String.localizedStringWithFormat(
                String(localized: "%lld rules", comment: "Profile subtitle: multiple sort rules."),
                Int64(ruleCount)
            ))
        }

        if preset.newTagExpiryDays > 0 {
            parts.append(String.localizedStringWithFormat(
                String(localized: "%lldd \u{201C}New\u{201D}", comment: "Profile subtitle: New-tag expiry in days."),
                Int64(preset.newTagExpiryDays)
            ))
        }

        let trimmedShortcut = preset.postSortShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedShortcut.isEmpty {
            parts.append("→ \(trimmedShortcut)")
        }

        if parts.isEmpty {
            return String(localized: "Default routing", comment: "Profile subtitle when no overrides set.")
        }
        return parts.joined(separator: " · ")
    }

    private func syncSelectedPresetSelection() {
        guard !prefs.savedPresets.isEmpty else {
            selectedPresetID = nil
            return
        }
        if selectedPresetID == nil || !prefs.savedPresets.contains(where: { $0.id == selectedPresetID }) {
            if let activeID = UUID(uuidString: prefs.activePresetID),
               prefs.savedPresets.contains(where: { $0.id == activeID }) {
                selectedPresetID = activeID
            } else {
                selectedPresetID = prefs.savedPresets.first?.id
            }
        }
    }

    private func createNewProfile() {
        var copy = prefs.savedPresets
        let preset = CompressionPreset(
            name: uniqueProfileName(
                baseName: String(localized: "New Profile", comment: "Default name for a newly created profile."),
                existingNames: Set(copy.map(\.name))
            ),
            from: prefs,
            format: prefs.defaultFormat
        )
        copy.append(preset)
        prefs.savedPresets = copy
        selectedPresetID = preset.id
    }

    private func duplicateSelectedProfile() {
        guard let idx = selectedPresetIndex else { return }
        var copy = prefs.savedPresets
        let source = copy[idx]
        let name = CompressionPreset.uniqueDuplicatePresetName(
            baseName: source.name,
            existingNames: Set(copy.map(\.name))
        )
        let duplicated = CompressionPreset(duplicating: source, name: name)
        copy.append(duplicated)
        prefs.savedPresets = copy
        selectedPresetID = duplicated.id
    }

    private func deleteSelectedProfile() {
        guard prefs.savedPresets.count > 1, let id = selectedPresetID else { return }
        var copy = prefs.savedPresets
        copy.removeAll { $0.id == id }
        prefs.savedPresets = copy
        selectedPresetID = copy.first?.id
        // If the deleted profile was active, fall back to the first remaining profile.
        if prefs.activePresetID == id.uuidString {
            prefs.activePresetID = copy.first?.id.uuidString ?? ""
        }
    }

    private func uniqueProfileName(baseName: String, existingNames: Set<String>) -> String {
        if !existingNames.contains(baseName) {
            return baseName
        }
        var index: Int64 = 2
        while true {
            let candidate = String.localizedStringWithFormat(
                String(localized: "%1$@ %2$lld", comment: "Auto-generated profile name with numeric suffix."),
                baseName,
                index
            )
            if !existingNames.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    private func inboxSortRulesBinding(presetIndex: Int) -> Binding<[InboxSortRule]> {
        Binding(
            get: { prefs.savedPresets[presetIndex].inboxSortRules },
            set: { newVal in
                var copy = prefs.savedPresets
                copy[presetIndex].inboxSortRules = newVal
                prefs.savedPresets = copy
            }
        )
    }

    private func profileNameBinding(presetIndex: Int) -> Binding<String> {
        Binding(
            get: { prefs.savedPresets[presetIndex].name },
            set: { newVal in
                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                var copy = prefs.savedPresets
                copy[presetIndex].name = trimmed
                prefs.savedPresets = copy
            }
        )
    }

    private func newTagExpiryBinding(presetIndex: Int) -> Binding<Int> {
        Binding(
            get: {
                let v = prefs.savedPresets[presetIndex].newTagExpiryDays
                return Self.newTagExpiryChoices.contains(v) ? v : 0
            },
            set: { newVal in
                var copy = prefs.savedPresets
                copy[presetIndex].newTagExpiryDays = newVal
                prefs.savedPresets = copy
            }
        )
    }

    private func postSortShortcutBinding(presetIndex: Int) -> Binding<String> {
        Binding(
            get: { prefs.savedPresets[presetIndex].postSortShortcutName },
            set: { newVal in
                var copy = prefs.savedPresets
                copy[presetIndex].postSortShortcutName = newVal
                prefs.savedPresets = copy
            }
        )
    }

    private func watchEnabledBinding(presetIndex: Int) -> Binding<Bool> {
        Binding(
            get: { prefs.savedPresets[presetIndex].watchFolderEnabled },
            set: { newVal in
                var copy = prefs.savedPresets
                copy[presetIndex].watchFolderEnabled = newVal
                if newVal && copy[presetIndex].watchFolderModeRaw.isEmpty {
                    copy[presetIndex].watchFolderModeRaw = "global"
                }
                prefs.savedPresets = copy
            }
        )
    }

    private func watchModeBinding(presetIndex: Int) -> Binding<String> {
        Binding(
            get: {
                let raw = prefs.savedPresets[presetIndex].watchFolderModeRaw
                return raw.isEmpty ? "global" : raw
            },
            set: { newVal in
                var copy = prefs.savedPresets
                copy[presetIndex].watchFolderModeRaw = newVal
                prefs.savedPresets = copy
            }
        )
    }

    private func pickWatchFolder(presetIndex: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Watch", comment: "Open panel: choose folder to watch.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var copy = prefs.savedPresets
        copy[presetIndex].watchFolderPath = url.path
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            copy[presetIndex].watchFolderBookmark = bookmark
        }
        prefs.savedPresets = copy
    }

    private func addCustomTag(presetIndex: Int) {
        let trimmed = newCustomTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var copy = prefs.savedPresets
        if copy[presetIndex].customFinderTags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            newCustomTagDraft = ""
            return
        }
        copy[presetIndex].customFinderTags.append(trimmed)
        prefs.savedPresets = copy
        newCustomTagDraft = ""
    }

    private func removeCustomTag(_ tag: String, presetIndex: Int) {
        var copy = prefs.savedPresets
        copy[presetIndex].customFinderTags.removeAll { $0 == tag }
        prefs.savedPresets = copy
    }

    private func newTagExpiryChoiceLabel(_ days: Int) -> String {
        switch days {
        case 0:
            return String(localized: "Off", comment: "New tag expiry choice.")
        case 1:
            return String(localized: "1 day", comment: "New tag expiry choice.")
        default:
            return String.localizedStringWithFormat(String(localized: "%lld days", comment: "New tag expiry choice."), Int64(days))
        }
    }
}

// MARK: - Watch Folders

private struct WatchFoldersTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Watch folder", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.folderWatchEnabled },
                    set: { prefs.folderWatchEnabled = $0 }
                ))
                if prefs.folderWatchEnabled {
                    HStack {
                        Text(prefs.watchedFolderPath.isEmpty
                             ? String(localized: "Watching Downloads (default)", comment: "Settings UI.")
                             : URL(fileURLWithPath: prefs.watchedFolderPath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose…", comment: "Settings UI.")) { pickGlobalWatchFolder() }
                            .buttonStyle(.bordered)
                    }
                    Text(String(localized: "This is the folder Binky monitors for new files. Where files are moved after sorting is configured in Output.", comment: "Settings UI."))
                    .font(.caption)
                        .foregroundStyle(.secondary)

                    PreferencesRelatedTabLink(title: String(localized: "Sidebar sections in Appearance…", comment: "Settings UI."), tab: .appearance)
                }
            } header: {
                Text(String(localized: "Watch Folder", comment: "Settings UI."))
            }

            Section {
                if prefs.savedPresets.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "No profiles yet. Create one under Profiles to attach another watched folder.", comment: "Settings UI."))
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
        return String(localized: "Global (Downloads default)", comment: "Watch row hint.")
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
