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
            .foregroundStyle(binkyTintColor)
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
    @State private var selectedTab: PreferencesTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem { Label(String(localized: "General", comment: "Settings UI."), systemImage: "gearshape") }
                .tag(PreferencesTab.general)
                .environmentObject(prefs)
            DestinationsTab()
                .tabItem { Label(String(localized: "Sorting", comment: "Settings tab: sort sorted folders and routing rules."), systemImage: "line.3.horizontal.decrease") }
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
        .frame(width: 540, height: 720)
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
    // Mirror the live `SMAppService.mainApp` status so the toggle stays in sync if the user changes it
    // from System Settings → General → Login Items while Binky is open.
    @State private var launchAtLoginEnabled: Bool = LaunchAtLoginManager.isEnabled
    @State private var confirmForgetDuplicateMemory = false

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
                            .foregroundStyle(binkyTintColor)
                    }
                }

                Toggle(String(localized: "Assign Finder tags when sorting", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.assignFinderTagsOnSortEnabled },
                    set: { prefs.assignFinderTagsOnSortEnabled = $0 }
                ))
                Text(String(localized: "Adds simple Finder tags (“New”, category hints) so files remain searchable.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PreferencesRelatedTabLink(
                    title: String(localized: "Routing & sorted folders…", comment: "Settings UI: link from General to Sorting tab for tag-related sorted folders."),
                    tab: .destinations
                )

                Toggle(String(localized: "Add the “New” Finder tag when sorting", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.sortAppendNewSemanticTagEnabled },
                    set: { prefs.sortAppendNewSemanticTagEnabled = $0 }
                ))
                .disabled(!prefs.assignFinderTagsOnSortEnabled)
                if !prefs.assignFinderTagsOnSortEnabled {
                    Text(String(localized: "Requires “Assign Finder tags when sorting”.", comment: "Settings UI."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if prefs.assignFinderTagsOnSortEnabled {
                    DisclosureGroup {
                        FinderTagDefaultsByCategoryMapEditor(
                            map: Binding(
                                get: { prefs.sortFinderTagDefaultsByCategory },
                                set: { prefs.sortFinderTagDefaultsByCategory = $0 }
                            )
                        )
                    } label: {
                        Text(String(localized: "Default tags by type", comment: "Settings: Finder tag defaults per sort category."))
                    }
                    Text(String(localized: "Leave blank to use Binky’s built-in hint for each type. Profile settings can override these per organizer.", comment: "Settings: Finder tag defaults footer."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                Picker(String(localized: "When Binky sees a duplicate file", comment: "Settings: duplicate handling."), selection: $prefs.sortDuplicateModeRaw) {
                    Text(String(localized: "Do nothing special", comment: "Duplicate mode off.")).tag(SortDuplicateHandlingMode.off.rawValue)
                    Text(String(localized: "Move to Duplicates folder", comment: "Duplicate mode.")).tag(SortDuplicateHandlingMode.moveToDuplicates.rawValue)
                    Text(String(localized: "Move to Trash", comment: "Duplicate mode.")).tag(SortDuplicateHandlingMode.moveToTrash.rawValue)
                }
                Text(String(localized: "Matches an identical file or a very similar image Binky already sorted.", comment: "Duplicate footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(String.localizedStringWithFormat(
                    String(localized: "Binky remembers %lld files.", comment: "Duplicate fingerprint database count."),
                    Int64(FileHashStore.shared.storedRecordCount())
                ))
                .font(.callout)
                if prefs.lastSortAlreadyHadCount > 0 {
                    Text(String.localizedStringWithFormat(
                        String(localized: "%lld already had in the last sort.", comment: "Last sort duplicate-style count."),
                        Int64(prefs.lastSortAlreadyHadCount)
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Button(String(localized: "Forget everything…", comment: "Clear duplicate memory database.")) {
                    confirmForgetDuplicateMemory = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .confirmationDialog(
                    String(localized: "Forget remembered files?", comment: "Clear hash store title."),
                    isPresented: $confirmForgetDuplicateMemory,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "Forget everything", comment: "Confirm clear duplicate memory."), role: .destructive) {
                        FileHashStore.shared.clearAllRecords()
                    }
                    Button(String(localized: "Keep it", comment: "Cancel clear duplicate memory."), role: .cancel) {}
                } message: {
                    Text(String(localized: "This clears Binky’s memory of files it’s seen. Duplicates won’t be recognized until they’re sorted again.", comment: "Clear hash store explanation."))
                }

                Toggle(String(localized: "Daily digest notification", comment: "Settings."), isOn: $prefs.dailyDigestEnabled)
                Stepper(value: $prefs.dailyDigestHour, in: 0...23) {
                    Text(String.localizedStringWithFormat(
                        String(localized: "Digest hour: %lld", comment: "Settings digest hour."),
                        Int64(prefs.dailyDigestHour)
                    ))
                }
                Text(String(localized: "One quiet summary of what Binky handled. Requires notification permission.", comment: "Digest footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } header: {
                Text(String(localized: "Housekeeping", comment: "Settings section."))
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
                .foregroundStyle(binkyTintColor)
            }

            Section {
                Toggle(String(localized: "Pause sorting on Low Power Mode", comment: "Settings: Energy section."), isOn: Binding(
                    get: { prefs.energyPauseOnLowPowerMode },
                    set: { prefs.energyPauseOnLowPowerMode = $0 }
                ))
                Toggle(String(localized: "Pause sorting when thermal state is critical", comment: "Settings: Energy section."), isOn: Binding(
                    get: { prefs.energyPauseOnThermalCritical },
                    set: { prefs.energyPauseOnThermalCritical = $0 }
                ))
                Stepper(value: Binding(
                    get: { prefs.energyBigBatchThreshold },
                    set: { prefs.energyBigBatchThreshold = $0 }
                ), in: 50...10_000, step: 50) {
                    Text(String.localizedStringWithFormat(
                        String(localized: "Big-batch threshold: %lld files", comment: "Settings: Energy section; file count before thermal pacing and progress coalescing."),
                        Int64(prefs.energyBigBatchThreshold)
                    ))
                }
                Picker(selection: Binding(
                    get: { prefs.energyThrottleProfile },
                    set: { prefs.energyThrottleProfile = $0 }
                )) {
                    Text(String(localized: "Auto", comment: "Settings: Energy throttle profile.")).tag(EnergyThrottleProfile.auto)
                    Text(String(localized: "Gentle", comment: "Settings: Energy throttle profile.")).tag(EnergyThrottleProfile.gentle)
                    Text(String(localized: "Aggressive", comment: "Settings: Energy throttle profile.")).tag(EnergyThrottleProfile.aggressive)
                } label: {
                    Text(String(localized: "Large-batch pacing", comment: "Settings: Energy throttle picker label."))
                }
                .pickerStyle(.segmented)
                Text(String(localized: "Applies to large sorts and watch-folder batches. Lower threshold means pacing starts sooner. Aggressive finishes faster when the Mac is warm; Gentle eases CPU and disk.", comment: "Settings: Energy section footnote."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(String(localized: "Energy", comment: "Settings: General tab section title."))
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
                .foregroundStyle(binkyTintColor)
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
                Text(String(localized: "Keeps watch-folder sorting awake even when the window is closed. Use the menu bar for Sort Now and History.", comment: "Settings UI: menu bar mode hint."))
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
                Toggle(String(localized: "Smart screenshot names (OCR)", comment: "Settings."), isOn: $prefs.sortSmartScreenshotNamesEnabled)
                Toggle(String(localized: "Detect receipts and invoices", comment: "Settings."), isOn: $prefs.sortDetectReceiptsEnabled)
                Text(String(localized: "Receipts use on-device text heuristics. Pauses when Low Power Mode pauses sorting.", comment: "Settings smart sort footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(String(localized: "Smart sorting", comment: "Settings section."))
            }

            Section {
                Toggle(String(localized: "Archive stale files", comment: "Settings aging."), isOn: $prefs.fileAgingEnabled)
                if prefs.fileAgingEnabled {
                    FileAgingRulesList(rules: Binding(
                        get: { prefs.fileAgingRules },
                        set: { prefs.fileAgingRules = $0 }
                    ))
                }
            } header: {
                Text(String(localized: "Stale files", comment: "Settings section: file aging."))
            } footer: {
                Text(String(localized: "Checks last opened, last used, and date added. Runs about once a day while Binky is open.", comment: "Aging footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "Custom routing rules", comment: "Output settings."), isOn: $prefs.sortCustomRulesEnabled)
                if prefs.sortCustomRulesEnabled {
                    SortRulesListEditor(
                        rules: Binding(
                            get: { prefs.sortRoutingRules },
                            set: { prefs.sortRoutingRules = $0 }
                        ),
                        enableGlobalCustomRulesOnAdd: true
                    )
                        .frame(minHeight: 200)
                }
            } header: {
                Text(String(localized: "Routing", comment: "Output settings."))
            } footer: {
                Text(String(localized: "First enabled rule wins. Rules run before automatic sorted folders (Images, Documents, Review folder, etc.).", comment: "Sorted folders tab routing section footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    Task {
                        let rows = await DownloadsSortOrchestrator.shared.previewInbox(prefs: prefs)
                        await MainActor.run {
                            previewRows = rows
                            showingPreview = true
                        }
                    }
                }
                Text(String(localized: "Shows where files in your watch folder would land. Nothing moves until you sort.", comment: "Output settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Dry run", comment: "Output settings."))
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingPreview) {
            SortPreviewSheet(rows: previewRows)
        }
    }
}

// MARK: - Inbox aging rules

private struct FileAgingPreviewSheet: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    let rule: CategoryAgingRule
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [FileAgingPreviewRow] = []

    private static let rowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "What would go", comment: "Aging preview sheet title."))
                .font(.title2.weight(.semibold))
            Text(String(localized: "Nothing is moved — this is a dry run.", comment: "Aging preview disclaimer."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if rows.isEmpty {
                Text(String(localized: "Nothing old enough to touch yet.", comment: "Aging preview empty."))
                    .frame(minHeight: 160)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.tertiary)
            } else {
                List(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.url.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        Text(String.localizedStringWithFormat(
                            String(localized: "Untouched about %lld days · last activity %@", comment: "Aging preview row."),
                            Int64(row.idleDays),
                            Self.rowDateFormatter.string(from: row.lastActivity)
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(row.actionSummary)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 220)
            }

            HStack {
                Spacer()
                Button(String(localized: "Close", comment: "Dismiss aging preview.")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(minWidth: 440, minHeight: 320)
        .onAppear {
            let root = prefs.activeSortSweepRootDirectory()
            rows = FileAgingService.shared.previewCandidates(rule: rule, root: root)
        }
    }
}

private struct FileAgingRulesList: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    @Binding var rules: [CategoryAgingRule]
    @State private var previewingRule: CategoryAgingRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rules.isEmpty {
                Text(String(localized: "No aging rules yet. Add one per category you want swept.", comment: "Aging rules empty state."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach($rules) { $rule in
                agingRuleRow($rule)
            }
            Button(String(localized: "Add aging rule", comment: "Aging rules add button.")) {
                rules.append(CategoryAgingRule.fresh())
            }
            .buttonStyle(.bordered)
        }
        .sheet(item: $previewingRule) { rule in
            FileAgingPreviewSheet(rule: rule)
                .environmentObject(prefs)
        }
    }

    @ViewBuilder
    private func agingRuleRow(_ rule: Binding<CategoryAgingRule>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(String(localized: "Category", comment: "Aging rule category."), selection: rule.categoryRaw) {
                ForEach(FileSortCategory.allCases, id: \.rawValue) { cat in
                    Text(Self.categoryLabel(cat)).tag(cat.rawValue)
                }
            }
            Stepper(value: rule.untouchedDays, in: 1...3650) {
                Text(String.localizedStringWithFormat(
                    String(localized: "Untouched %lld days", comment: "Aging rule days."),
                    Int64(rule.wrappedValue.untouchedDays)
                ))
            }
            Picker(String(localized: "Then", comment: "Aging rule action."), selection: rule.action) {
                Text(String(localized: "Archive", comment: "Aging action.")).tag(FileAgingAction.archive)
                Text(String(localized: "Trash", comment: "Aging action.")).tag(FileAgingAction.trash)
            }
            .pickerStyle(.segmented)
            if rule.wrappedValue.action == .archive {
                TextField(
                    String(localized: "Archive subfolder", comment: "Aging archive path."),
                    text: rule.archiveFolderRelative
                )
                .textFieldStyle(.roundedBorder)
            }
            Button(String(localized: "See what would go", comment: "Aging rule dry-run preview.")) {
                previewingRule = rule.wrappedValue
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            HStack {
                Spacer()
                Button(String(localized: "Remove", comment: "Remove aging rule.")) {
                    rules.removeAll { $0.id == rule.wrappedValue.id }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
    }

    private static func categoryLabel(_ category: FileSortCategory) -> String {
        switch category {
        case .images: return String(localized: "Images", comment: "Sort category.")
        case .pdf: return String(localized: "PDF", comment: "Sort category.")
        case .video: return String(localized: "Video", comment: "Sort category.")
        case .audio: return String(localized: "Audio", comment: "Sort category.")
        case .documents: return String(localized: "Documents", comment: "Sort category.")
        case .archives: return String(localized: "Archives", comment: "Sort category.")
        case .apps: return String(localized: "Apps / installers", comment: "Sort category.")
        case .screenshots: return String(localized: "Screenshots", comment: "Sort category.")
        case .misc: return String(localized: "Misc", comment: "Sort category.")
        case .review: return String(localized: "Review", comment: "Sort category.")
        case .duplicates: return String(localized: "Duplicates", comment: "Sort category.")
        case .receipts: return String(localized: "Receipts", comment: "Sort category.")
        }
    }
}

// MARK: - Routing rules (list + sheet editor)

struct RuleEditorSheetState: Identifiable {
    var draft: InboxSortRule
    let isNew: Bool
    let showDescribeSection: Bool
    var id: UUID { draft.id }
}

private func ruleSummaryLine(_ rule: InboxSortRule) -> String {
    var parts: [String] = []
    if !rule.matchExtensions.isEmpty {
        parts.append(rule.matchExtensions.joined(separator: ", "))
    }
    if !rule.nameContains.isEmpty {
        parts.append(
            String.localizedStringWithFormat(
                String(localized: "name has “%@”", comment: "Rule summary fragment; filename substring."),
                rule.nameContains
            )
        )
    }
    if !rule.originDomains.isEmpty {
        let shown = rule.originDomains.prefix(2).joined(separator: ", ")
        let more = rule.originDomains.count > 2 ? String(localized: "…", comment: "Ellipsis for truncated list.") : ""
        parts.append(
            String.localizedStringWithFormat(
                String(localized: "from %@%@", comment: "Rule summary fragment; origin domains."),
                shown,
                more
            )
        )
    }
    if rule.fileKindFilter != .any {
        parts.append(rule.fileKindFilter.localizedTitle)
    }
    if rule.contentMatch.kind != .none {
        parts.append(rule.contentMatch.kind.localizedTitle)
    }
    let dest = rule.destinationRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
    let destPart = dest.isEmpty
        ? String(localized: "(no folder)", comment: "Rule summary when destination empty.")
        : dest
    let head = parts.joined(separator: " · ")
    if head.isEmpty {
        return String.localizedStringWithFormat(
            String(localized: "→ %@", comment: "Rule summary when no conditions; arrow to destination."),
            destPart
        )
    }
    return String.localizedStringWithFormat(
        String(localized: "%@ → %@", comment: "Rule summary: conditions then arrow destination."),
        head,
        destPart
    )
}

private struct SortRulesListEditor: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    @Binding var rules: [InboxSortRule]
    var enableGlobalCustomRulesOnAdd: Bool = false
    @State private var editorSheet: RuleEditorSheetState?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rules.isEmpty {
                Text(String(localized: "No rules yet. Use the buttons below.", comment: "Routing rules empty hint."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            List {
                ForEach(Array(rules.enumerated()), id: \.element.id) { _, rule in
                    ruleRow(rule: rule)
                }
                .onMove { source, destination in
                    rules.move(fromOffsets: source, toOffset: destination)
                }
            }
            .frame(minHeight: 160)
            HStack(spacing: 12) {
                Button(String(localized: "Describe a rule…", comment: "Routing rules: add via natural language.")) {
                    let next = rules.count + 1
                    editorSheet = RuleEditorSheetState(
                        draft: InboxSortRule.fresh(order: next),
                        isNew: true,
                        showDescribeSection: true
                    )
                }
                .buttonStyle(.bordered)
                Button(String(localized: "Add manually", comment: "Routing rules: add blank rule.")) {
                    let next = rules.count + 1
                    editorSheet = RuleEditorSheetState(
                        draft: InboxSortRule.fresh(order: next),
                        isNew: true,
                        showDescribeSection: false
                    )
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
            }
        }
        .sheet(item: $editorSheet) { state in
            RuleEditorSheet(
                state: state,
                onCancel: { editorSheet = nil },
                onSave: { saved in
                    if state.isNew {
                        rules.append(saved)
                        if enableGlobalCustomRulesOnAdd {
                            prefs.sortCustomRulesEnabled = true
                        }
                    } else if let idx = rules.firstIndex(where: { $0.id == saved.id }) {
                        rules[idx] = saved
                    }
                    editorSheet = nil
                }
            )
            .environmentObject(prefs)
        }
    }

    private func isEnabledBinding(for ruleID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                rules.first(where: { $0.id == ruleID })?.isEnabled ?? false
            },
            set: { newVal in
                guard let idx = rules.firstIndex(where: { $0.id == ruleID }) else { return }
                var c = rules
                c[idx].isEnabled = newVal
                rules = c
            }
        )
    }

    @ViewBuilder
    private func ruleRow(rule: InboxSortRule) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(
                String(),
                isOn: isEnabledBinding(for: rule.id)
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(String(localized: "Enabled", comment: "Routing rule list toggle."))

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(ruleSummaryLine(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                editorSheet = RuleEditorSheetState(draft: rule, isNew: false, showDescribeSection: false)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(String(localized: "Edit…", comment: "Routing rule context menu.")) {
                editorSheet = RuleEditorSheetState(draft: rule, isNew: false, showDescribeSection: false)
            }
            Button(String(localized: "Delete", comment: "Routing rule context menu."), role: .destructive) {
                rules.removeAll { $0.id == rule.id }
            }
        }
    }
}

struct RuleEditorSheet: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    @State private var draft: InboxSortRule
    private let showDescribeSection: Bool
    private let isNew: Bool
    private let onCancel: () -> Void
    private let onSave: (InboxSortRule) -> Void

    @State private var nlPhrase: String = ""
    @State private var nlWorking: Bool = false
    @State private var nlParsedDraft: InboxSortRule?
    @FocusState private var nlFieldFocused: Bool

    init(state: RuleEditorSheetState, onCancel: @escaping () -> Void, onSave: @escaping (InboxSortRule) -> Void) {
        _draft = State(initialValue: state.draft)
        showDescribeSection = state.showDescribeSection
        isNew = state.isNew
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var ignoreDatePredicateKind: SortDateAddedPredicateKind {
        SortDateAddedPredicateKind(rawValue: "none") ?? .olderThanDays
    }

    private var extensionsBinding: Binding<String> {
        Binding(
            get: { draft.matchExtensions.joined(separator: ", ") },
            set: { newVal in
                var c = draft
                let parts = newVal.split(separator: ",").map { chunk in
                    String(chunk).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        .replacingOccurrences(of: ".", with: "")
                }.filter { !$0.isEmpty }
                c.matchExtensions = parts
                draft = c
            }
        )
    }

    private var addedTagsBinding: Binding<String> {
        Binding(
            get: { draft.addedTags.joined(separator: ", ") },
            set: { newVal in
                var c = draft
                let parts = newVal.split(separator: ",").map { chunk in
                    String(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                c.addedTags = parts
                draft = c
            }
        )
    }

    private var categoryDefaultReplacementTagsBinding: Binding<String> {
        Binding(
            get: { draft.categoryDefaultReplacementTags.joined(separator: ", ") },
            set: { newVal in
                var c = draft
                let parts = newVal.split(separator: ",").map { chunk in
                    String(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                c.categoryDefaultReplacementTags = parts
                draft = c
            }
        )
    }

    private var originDomainsBinding: Binding<String> {
        Binding(
            get: { draft.originDomains.joined(separator: "\n") },
            set: { newVal in
                var c = draft
                let lines = newVal.split(whereSeparator: \.isNewline).map {
                    String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }.filter { !$0.isEmpty }
                c.originDomains = lines
                draft = c
            }
        )
    }

    private var contentMatchKindBinding: Binding<SortContentMatchKind> {
        Binding(
            get: { draft.contentMatch.kind },
            set: { newKind in
                var c = draft
                c.contentMatch = SortContentMatch(kind: newKind)
                draft = c
            }
        )
    }

    private func binding<T>(_ keyPath: WritableKeyPath<InboxSortRule, T>) -> Binding<T> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newVal in
                var c = draft
                c[keyPath: keyPath] = newVal
                draft = c
            }
        )
    }

    private var minSizeBinding: Binding<String> {
        Binding(
            get: {
                if let b = draft.minSizeBytes { return "\(b)" }
                return ""
            },
            set: { raw in
                var c = draft
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                c.minSizeBytes = trimmed.isEmpty ? nil : Int64(trimmed)
                draft = c
            }
        )
    }

    private var maxSizeBinding: Binding<String> {
        Binding(
            get: {
                if let b = draft.maxSizeBytes { return "\(b)" }
                return ""
            },
            set: { raw in
                var c = draft
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                c.maxSizeBytes = trimmed.isEmpty ? nil : Int64(trimmed)
                draft = c
            }
        )
    }

    private var dateKindBinding: Binding<SortDateAddedPredicateKind> {
        Binding(
            get: { draft.dateAddedPredicate?.kind ?? ignoreDatePredicateKind },
            set: { newKind in
                var c = draft
                if newKind == ignoreDatePredicateKind {
                    c.dateAddedPredicate = nil
                } else {
                    let days = c.dateAddedPredicate?.days ?? 7
                    c.dateAddedPredicate = SortDateAddedPredicate(kind: newKind, days: max(0, days))
                }
                draft = c
            }
        )
    }

    private var dateDaysBinding: Binding<Int> {
        Binding(
            get: { draft.dateAddedPredicate?.days ?? 7 },
            set: { newDays in
                var c = draft
                let kind = c.dateAddedPredicate?.kind ?? SortDateAddedPredicateKind.olderThanDays
                guard kind != ignoreDatePredicateKind else { return }
                c.dateAddedPredicate = SortDateAddedPredicate(kind: kind, days: max(0, newDays))
                draft = c
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(String(localized: "Enabled", comment: "Rule editor."), isOn: binding(\.isEnabled))
                    TextField(String(localized: "Rule name", comment: "Rule editor."), text: binding(\.name))
                } header: {
                    Text(String(localized: "Rule", comment: "Rule editor sheet section."))
                }

                if showDescribeSection {
                    Section {
                        TextField(
                            String(localized: "Describe a rule (e.g. from figma.com to Design/Figma)", comment: "NL rule placeholder."),
                            text: $nlPhrase
                        )
                        .textFieldStyle(.roundedBorder)
                        .focused($nlFieldFocused)
                        HStack(spacing: 12) {
                            Button(String(localized: "Generate", comment: "Apply natural language to rule fields.")) {
                                generateFromPhrase()
                            }
                            .disabled(nlPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nlWorking)
                            if nlWorking {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Spacer(minLength: 0)
                        }
                        if #unavailable(macOS 26.0) {
                            Text(String(localized: "On macOS 26, Generate can use on-device models when available. Earlier macOS still fills the form with phrase heuristics.", comment: "NL availability hint in rule sheet."))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let pending = nlParsedDraft {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(String(localized: "Here’s what Binky heard.", comment: "NL rule parse preview header."))
                                    .font(.subheadline.weight(.semibold))
                                Text(RuleEditorSheet.nlPreviewDetailLines(pending))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 12) {
                                    Button(String(localized: "Looks right. Save it.", comment: "Apply NL parse to editor form.")) {
                                        applyNLProposed(pending)
                                    }
                                    .keyboardShortcut(.defaultAction)
                                    Button(String(localized: "Not quite. Try again.", comment: "Dismiss NL parse preview.")) {
                                        nlParsedDraft = nil
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(String(localized: "Describe", comment: "Rule editor sheet: NL section."))
                    } footer: {
                        Text(String(localized: "Fills the sections below. You can edit every field before saving.", comment: "Rule editor NL footer."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField(String(localized: "Extensions (comma-separated, empty = any)", comment: "Rule editor."), text: extensionsBinding)
                        .textFieldStyle(.roundedBorder)
                    TextField(String(localized: "Filename contains (empty = any)", comment: "Rule editor."), text: binding(\.nameContains))
                        .textFieldStyle(.roundedBorder)
                    Text(String(localized: "Downloaded from — one host per line (*.stripe.com, figma.com)", comment: "Rule editor where-froms."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextEditor(text: originDomainsBinding)
                        .frame(minHeight: 52)
                        .font(.system(.body, design: .monospaced))
                    Picker(String(localized: "File kind", comment: "Rule editor."), selection: binding(\.fileKindFilter)) {
                        ForEach(SortFileKindFilter.allCases) { filter in
                            Text(filter.localizedTitle).tag(filter)
                        }
                    }
                    Picker(String(localized: "Content match", comment: "Rule editor."), selection: contentMatchKindBinding) {
                        ForEach(SortContentMatchKind.allCases) { kind in
                            Text(kind.localizedTitle).tag(kind)
                        }
                    }
                    HStack {
                        TextField(String(localized: "Min size (bytes)", comment: "Rule editor."), text: minSizeBinding)
                            .textFieldStyle(.roundedBorder)
                        TextField(String(localized: "Max size (bytes)", comment: "Rule editor."), text: maxSizeBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                    Picker(String(localized: "Date added", comment: "Rule editor."), selection: dateKindBinding) {
                        Text(String(localized: "Ignore", comment: "Rule editor.")).tag(ignoreDatePredicateKind)
                        Text(String(localized: "Added within last … days", comment: "Rule editor.")).tag(SortDateAddedPredicateKind.newerThanDays)
                        Text(String(localized: "Added more than … days ago", comment: "Rule editor.")).tag(SortDateAddedPredicateKind.olderThanDays)
                    }
                    if let predicate = draft.dateAddedPredicate,
                       predicate.kind != ignoreDatePredicateKind {
                        Stepper(value: dateDaysBinding, in: 0...3650) {
                            Text(String.localizedStringWithFormat(String(localized: "Days: %lld", comment: "Rule editor."), Int64(dateDaysBinding.wrappedValue)))
                        }
                    }
                } header: {
                    Text(String(localized: "When this matches", comment: "Rule editor sheet section."))
                }

                Section {
                    TextField(String(localized: "Destination subfolder", comment: "Rule editor."), text: binding(\.destinationRelativePath))
                        .textFieldStyle(.roundedBorder)
                    if DinkyBridge.isInstalled {
                        Button(String(localized: "Watch in Dinky →", comment: "Routing rule: open destination in Dinky.")) {
                            let trimmed = draft.destinationRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
                            let root = prefs.downloadsSortRootDirectory()
                            let folder = trimmed.isEmpty ? root : root.appendingPathComponent(trimmed, isDirectory: true)
                            _ = DinkyBridge.openFolder(folder)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(binkyTintColor)
                        .accessibilityLabel(String(localized: "Open sorted folder in Dinky", comment: "VoiceOver routing rule helper."))
                    }
                } header: {
                    Text(String(localized: "Then move to", comment: "Rule editor sheet section."))
                }

                Section {
                    Picker(String(localized: "Rename", comment: "Rule editor."), selection: binding(\.renameStyle)) {
                        ForEach(SortRenameStyle.allCases) { style in
                            Text(style.localizedTitle).tag(style)
                        }
                    }
                    if draft.renameStyle == .template {
                        TextField("{date} {stem}{ext}", text: binding(\.renameTemplate))
                            .textFieldStyle(.roundedBorder)
                        Text(String(localized: "Tokens: {date}, {stem}, {ext}, {n}, {origin}, {ocr}, {vendor}, {amount}", comment: "Rule editor rename hint."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String(localized: "Then rename", comment: "Rule editor sheet section."))
                }

                Section {
                    TextField(String(localized: "Tags on match (comma-separated)", comment: "Rule editor."), text: addedTagsBinding)
                        .textFieldStyle(.roundedBorder)
                    Picker(String(localized: "Category tags when this rule matches", comment: "Rule editor: Finder tag policy."), selection: binding(\.finderTagPolicy)) {
                        Text(String(localized: "Use defaults for file type", comment: "Rule editor: additive Finder tag policy.")).tag(SortRuleFinderTagPolicy.additive)
                        Text(String(localized: "Replace type defaults", comment: "Rule editor: replace category Finder tags.")).tag(SortRuleFinderTagPolicy.replaceCategoryDefault)
                    }
                    if draft.finderTagPolicy == .replaceCategoryDefault {
                        TextField(String(localized: "Replacement tags (comma-separated)", comment: "Rule editor: tags that replace category defaults."), text: categoryDefaultReplacementTagsBinding)
                            .textFieldStyle(.roundedBorder)
                        Text(String(localized: "Replaces only the type-based tags. Profile tags and “Tags on match” still apply after.", comment: "Rule editor: replace tags hint."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(String(localized: "Tag the file", comment: "Rule editor sheet section."))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(
                isNew
                    ? String(localized: "New rule", comment: "Rule editor sheet title.")
                    : String(localized: "Edit rule", comment: "Rule editor sheet title.")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Rule editor sheet.")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", comment: "Rule editor sheet.")) { onSave(draft) }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear {
            if showDescribeSection {
                nlFieldFocused = true
            }
        }
    }

    private func generateFromPhrase() {
        Task {
            nlWorking = true
            defer { nlWorking = false }
            let built = await RuleSynthesizer.synthesize(from: nlPhrase, order: 1)
            await MainActor.run {
                nlParsedDraft = built
            }
        }
    }

    private func applyNLProposed(_ proposed: InboxSortRule) {
        var merged = proposed
        merged.id = draft.id
        draft = merged
        nlParsedDraft = nil
        nlPhrase = ""
    }

    private static func nlPreviewDetailLines(_ rule: InboxSortRule) -> String {
        var lines: [String] = []
        lines.append(String.localizedStringWithFormat(String(localized: "Name: %@", comment: "NL preview field."), rule.name))
        if rule.originDomains.isEmpty {
            lines.append(String(localized: "From: any", comment: "NL preview field."))
        } else {
            lines.append(String.localizedStringWithFormat(
                String(localized: "From: %@", comment: "NL preview field."),
                rule.originDomains.joined(separator: ", ")
            ))
        }
        let dest = rule.destinationRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(String.localizedStringWithFormat(
            String(localized: "Goes to: %@", comment: "NL preview field."),
            dest.isEmpty ? String(localized: "(not set)", comment: "NL preview empty destination.") : dest
        ))
        lines.append(String.localizedStringWithFormat(
            String(localized: "File kind: %@", comment: "NL preview field."),
            rule.fileKindFilter.localizedTitle
        ))
        lines.append(String.localizedStringWithFormat(
            String(localized: "Content: %@", comment: "NL preview field."),
            rule.contentMatch.kind.localizedTitle
        ))
        return lines.joined(separator: "\n")
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

                Section(String(localized: "Default tags by type", comment: "Profile editor: per-category Finder tag overrides.")) {
                    Text(String(localized: "Overrides global defaults for files sorted under this profile. Leave blank to inherit.", comment: "Profile editor: per-type tag hint."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    FinderTagDefaultsByCategoryMapEditor(map: finderTagDefaultsBinding(presetIndex: idx))
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
                        Text(String(localized: "No rules. Binky uses default sorted folders.", comment: "Profile editor: empty rules."))
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
                        .foregroundStyle(binkyTintColor)
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
        .foregroundStyle(binkyTintColor)
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
            )
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

    private func finderTagDefaultsBinding(presetIndex: Int) -> Binding<[String: [String]]> {
        Binding(
            get: { prefs.savedPresets[presetIndex].finderTagDefaultsByCategory },
            set: { newVal in
                var copy = prefs.savedPresets
                copy[presetIndex].finderTagDefaultsByCategory = newVal
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
                    Text(String(localized: "This is the folder Binky monitors for new files. Where files are moved after sorting is configured in Sorted folders.", comment: "Settings UI."))
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

/// Comma-separated tags per ``FileSortCategory`` (persisted as `[rawValue: [tags]]`).
private struct FinderTagDefaultsByCategoryMapEditor: View {
    @Binding var map: [String: [String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(FileSortCategory.allCases, id: \.rawValue) { category in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.rowTitle(for: category))
                        .font(.subheadline.weight(.medium))
                    TextField(
                        String(localized: "Tags, comma-separated", comment: "Placeholder for per-type Finder tag list."),
                        text: binding(for: category)
                    )
                    .textFieldStyle(.roundedBorder)
                    Text(String.localizedStringWithFormat(
                        String(localized: "Built-in hint: %@", comment: "Settings: shows default Finder tag hint for a sort type."),
                        Self.builtInHint(for: category)
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func binding(for category: FileSortCategory) -> Binding<String> {
        Binding(
            get: { map[category.rawValue]?.joined(separator: ", ") ?? "" },
            set: { newVal in
                var copy = map
                let parts = newVal.split(separator: ",").map { chunk in
                    String(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                if parts.isEmpty {
                    copy.removeValue(forKey: category.rawValue)
                } else {
                    copy[category.rawValue] = parts
                }
                map = copy
            }
        )
    }

    private static func builtInHint(for category: FileSortCategory) -> String {
        category.semanticTagHint
    }

    private static func rowTitle(for category: FileSortCategory) -> String {
        switch category {
        case .images:
            return String(localized: "Images", comment: "Sort category label for Finder tag defaults.")
        case .pdf:
            return String(localized: "PDF", comment: "Sort category label for Finder tag defaults.")
        case .video:
            return String(localized: "Video", comment: "Sort category label for Finder tag defaults.")
        case .audio:
            return String(localized: "Audio", comment: "Sort category label for Finder tag defaults.")
        case .documents:
            return String(localized: "Documents", comment: "Sort category label for Finder tag defaults.")
        case .archives:
            return String(localized: "Archives", comment: "Sort category label for Finder tag defaults.")
        case .apps:
            return String(localized: "Apps / installers", comment: "Sort category label for Finder tag defaults.")
        case .screenshots:
            return String(localized: "Screenshots", comment: "Sort category label for Finder tag defaults.")
        case .misc:
            return String(localized: "Misc", comment: "Sort category label for Finder tag defaults.")
        case .review:
            return String(localized: "Review", comment: "Sort category label for Finder tag defaults.")
        case .duplicates:
            return String(localized: "Duplicates", comment: "Sort category label for Finder tag defaults.")
        case .receipts:
            return String(localized: "Receipts", comment: "Sort category label for Finder tag defaults.")
        }
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
