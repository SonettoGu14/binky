import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Main window: slim Binky behavior sidebar + recent sort activity (not a compression dropzone).
struct OrganizerMainView: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @EnvironmentObject var updater: UpdateChecker
    @ObservedObject var vm: OrganizerViewModel
    @ObservedObject private var diagnostics = DiagnosticsReporter.shared

    @StateObject private var folderWatcher = FolderWatcher()

    @State private var isDropTargeted = false
    @State private var isSorting = false
    @State private var showingHistorySheet = false

    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let absoluteTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationSplitView {
            slimOrganizerSidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
        } detail: {
            activityMainPane
                .frame(minWidth: 440, minHeight: 440)
                .background(.ultraThinMaterial)
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        }
        .task {
            await updater.check()
        }
        .onAppear {
            handleAppear()
        }
        .onReceive(NotificationCenter.default.publisher(for: .binkyShowHistory)) { _ in
            showingHistorySheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            updateFolderWatcher()
        }
        .onChange(of: prefs.folderWatchEnabled) { _, _ in updateFolderWatcher() }
        .onChange(of: prefs.watchedFolderPath) { _, _ in updateFolderWatcher() }
        .onChange(of: prefs.watchedFolderBookmark) { _, _ in updateFolderWatcher() }
        .onChange(of: prefs.savedPresetsData) { _, _ in updateFolderWatcher() }
        .sheet(isPresented: $showingHistorySheet) {
            HistorySheet(
                onOpenSessionSummary: { record in
                    guard let data = record.batchSummaryData else { return }
                    if let sortOutcome = try? JSONDecoder().decode(SortBatchOutcome.self, from: data) {
                        showingHistorySheet = false
                        vm.presentHistoricalSortOutcome(sortOutcome)
                    }
                }
            )
            .environmentObject(prefs)
        }
        .sheet(item: $vm.pendingSortOutcome) { outcome in
            SortOutcomeSheet(
                outcome: outcome,
                onUndo: { vm.applySortOutcomeDismissalDefaults() },
                onDismiss: { vm.applySortOutcomeDismissalDefaults() }
            )
        }
        .sheet(item: $diagnostics.pendingCrashReport) { report in
            PostCrashReportSheet(report: report, diagnostics: diagnostics)
        }
        .onReceive(NotificationCenter.default.publisher(for: .binkyPrepareQuit)) { _ in
            vm.pendingSortOutcome = nil
            diagnostics.pendingCrashReport = nil
            showingHistorySheet = false
        }
    }

    // MARK: - Sidebar (Binky only)

    private var slimOrganizerSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionHeading(
                        icon: "person.crop.circle",
                        title: String(localized: "Profile", comment: "Organizer sidebar profile section.")
                    )

                    profileSelectionRows
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.03)))

                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionHeading(
                        icon: "slider.horizontal.3",
                        title: String(localized: "Settings", comment: "Organizer sidebar settings header.")
                    )

                    Toggle(String(localized: "Watch this folder for new files", comment: "Watch toggle."), isOn: Binding(
                        get: { prefs.folderWatchEnabled },
                        set: { prefs.folderWatchEnabled = $0 }
                    ))
                    .font(.system(size: 11))

                    if prefs.folderWatchEnabled {
                        HStack(spacing: 8) {
                            Text(prefs.watchedFolderPath.isEmpty
                                 ? String(localized: "No folder selected", comment: "Watch folder unset label.")
                                 : URL(fileURLWithPath: prefs.watchedFolderPath).lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            Button(String(localized: "Choose…", comment: "Watch folder chooser button.")) {
                                pickGlobalWatchFolder()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Toggle(String(localized: "Notify when done", comment: "Settings UI."), isOn: Binding(
                        get: { prefs.notifyWhenDone },
                        set: { prefs.notifyWhenDone = $0 }
                    ))
                    .font(.system(size: 11))

                    Toggle(String(localized: "Show summaries after sorting", comment: "Settings UI."), isOn: Binding(
                        get: { prefs.showBatchSummaryDialog },
                        set: { prefs.showBatchSummaryDialog = $0 }
                    ))
                    .font(.system(size: 11))

                    Toggle(String(localized: "Open inbox in Finder when done", comment: "Settings UI."), isOn: Binding(
                        get: { prefs.openFolderWhenDone },
                        set: { prefs.openFolderWhenDone = $0 }
                    ))
                    .font(.system(size: 11))

                    sidebarShortcutRow(
                        title: String(localized: "Open full history…", comment: ""),
                        systemImage: "clock"
                    ) {
                        showingHistorySheet = true
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.03)))

                VStack(alignment: .leading, spacing: 4) {
                    settingsSectionHeading(
                        icon: "arrow.up.right.square",
                        title: String(localized: "Additional settings", comment: "Organizer sidebar extra settings header.")
                    )
                    organizerSettingsSidebarLink(
                        tab: .profiles,
                        title: String(localized: "Presets", comment: "Organizer sidebar shortcut to profiles tab."),
                        systemImage: "slider.horizontal.3"
                    )
                    organizerSettingsSidebarLink(
                        tab: .watch,
                        title: String(localized: "Watch folders", comment: "Organizer sidebar shortcut to watch tab."),
                        systemImage: "eye"
                    )
                    organizerSettingsSidebarLink(
                        tab: .general,
                        title: String(localized: "All settings", comment: "Organizer sidebar shortcut to general settings tab."),
                        systemImage: "gearshape"
                    )
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.03)))
            }
            .padding(10)
        }
    }

    private var activePreset: CompressionPreset? {
        guard let id = UUID(uuidString: prefs.activePresetID) else { return nil }
        return prefs.savedPresets.first(where: { $0.id == id })
    }

    private var profileSelectionRows: some View {
        VStack(spacing: 3) {
            profileSelectionRow(
                name: String(localized: "Default", comment: "Organizer sidebar default profile row title."),
                subtitle: String(localized: "Built-in default routing rules.", comment: "Organizer sidebar default profile row subtitle."),
                isActive: prefs.activePresetID.isEmpty
            ) {
                prefs.activePresetID = ""
            }

            ForEach(prefs.savedPresets) { preset in
                profileSelectionRow(
                    name: preset.name,
                    subtitle: preset.includedMediaTypesSummaryLabel,
                    isActive: prefs.activePresetID == preset.id.uuidString
                ) {
                    prefs.activePresetID = preset.id.uuidString
                }
            }
        }
    }

    @ViewBuilder
    private func profileSelectionRow(
        name: String,
        subtitle: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.25))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    /// Opens the Settings scene (``SettingsLink``) and matches the row styling of legacy sidebar links.
    private func organizerSettingsSidebarLink(tab: PreferencesTab, title: String, systemImage: String) -> some View {
        SettingsLink {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .simultaneousGesture(TapGesture().onEnded {
            PreferencesTab.stagePendingTab(tab)
        })
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    /// Dinky-style sidebar row: leading SF Symbol, accent label, trailing chevron, plain hit area.
    private func sidebarShortcutRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
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

    // MARK: - Main: activity feed

    private var activityMainPane: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                statusHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                if showReviewBanner {
                    reviewBanner
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                Divider()
                    .opacity(0.35)

                activitySection
            }

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.full")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Watched inbox", comment: "Organizer: label above inbox path."))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(prefs.downloadsSortRootDirectory().path)
                        .font(.callout.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                if isSorting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Toggle(String(localized: "Watch", comment: "Short watch toggle in organizer header."), isOn: Binding(
                        get: { prefs.folderWatchEnabled },
                        set: { prefs.folderWatchEnabled = $0 }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.subheadline)

                    Button {
                        openInboxInFinder()
                    } label: {
                        Text(String(localized: "Show Inbox in Finder", comment: "Reveal inbox."))
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)

                    Spacer(minLength: 0)
                }

                Button {
                    Task { await runSortWork { await vm.runInteractiveDownloadsSweep(prefs: prefs) } }
                } label: {
                    Text(String(localized: "Sort Now", comment: "Primary sort button."))
                }
                .buttonStyle(.borderedProminent)
                .fixedSize()
            }

            if let last = lastSortDate {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "Last sort: %@", comment: "Organizer header; argument is relative time string."),
                            Self.relativeTimeFormatter.localizedString(for: last, relativeTo: context.date)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var reviewBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Pending review", comment: "Organizer banner when review bucket has items."))
                    .font(.subheadline.weight(.semibold))
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "%lld item(s) may need a look in Review.", comment: "Organizer banner detail; review count."),
                        reviewBannerCount
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(String(localized: "Open Review in Finder", comment: "Reveal review bucket.")) {
                openReviewInFinder()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    @ViewBuilder
    private var activitySection: some View {
        let rows = sortHistoryRows
        if rows.isEmpty {
            emptyActivityState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Recent activity", comment: "Organizer main section title."))
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            activityRow(row)
                            Divider()
                                .opacity(0.2)
                                .padding(.leading, 20)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var emptyActivityState: some View {
        OrganizerEmptyStateView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activityRow(_ row: SortHistoryRowModel) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.absoluteTimeFormatter.string(from: row.record.timestamp))
                    .font(.subheadline.weight(.semibold))
                Text(countSummary(for: row.outcome))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Button(String(localized: "Open Summary…", comment: "History row: reopen stored batch completion dialog.")) {
                    vm.presentHistoricalSortOutcome(row.outcome)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(String(localized: "Show Inbox in Finder", comment: "Reveal inbox.")) {
                    openInboxInFinder()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Models / derived state

    private struct SortHistoryRowModel: Identifiable {
        let id: UUID
        let record: SessionRecord
        let outcome: SortBatchOutcome
    }

    private var sortHistoryRows: [SortHistoryRowModel] {
        prefs.sessionHistory.compactMap { record in
            guard let data = record.batchSummaryData,
                  let outcome = try? JSONDecoder().decode(SortBatchOutcome.self, from: data) else { return nil }
            return SortHistoryRowModel(id: record.id, record: record, outcome: outcome)
        }
    }

    private var lastSortDate: Date? {
        if let d = vm.lastSortOutcome?.started { return d }
        return sortHistoryRows.first?.record.timestamp
    }

    private var showReviewBanner: Bool {
        reviewFolderItemCount > 0 || (vm.lastSortOutcome?.reviewQueuedCount ?? 0) > 0
    }

    private var reviewBannerCount: Int64 {
        max(
            Int64(reviewFolderItemCount),
            Int64(vm.lastSortOutcome?.reviewQueuedCount ?? 0)
        )
    }

    private var reviewFolderItemCount: Int {
        let root = prefs.downloadsSortRootDirectory()
        let reviewURL = root.appendingPathComponent(FileSortCategory.review.downloadsSubfolder, isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: reviewURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
        }.count
    }

    private func countSummary(for outcome: SortBatchOutcome) -> String {
        String.localizedStringWithFormat(
            String(localized: "%1$lld moved · %2$lld kept · %3$lld skipped · %4$lld review", comment: "Organizer activity row; four integer counts."),
            Int64(outcome.movedCount),
            Int64(outcome.keptCount),
            Int64(outcome.skippedCount),
            Int64(outcome.reviewQueuedCount)
        )
    }

    // MARK: - Actions

    @MainActor
    private func runSortWork(_ work: @escaping () async -> Void) async {
        isSorting = true
        defer { isSorting = false }
        await work()
    }

    private func openInboxInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: prefs.downloadsSortRootDirectory().path)
    }

    private func openReviewInFinder() {
        let root = prefs.downloadsSortRootDirectory()
        let reviewURL = root.appendingPathComponent(FileSortCategory.review.downloadsSubfolder, isDirectory: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: reviewURL.path)
    }

    private func handleAppear() {
        updateFolderWatcher()
    }

    private func updateFolderWatcher() {
        prefs.reconcileFolderBookmarksIfNeeded()
        let reg = WatchPipelineRegistry(prefs: prefs)
        let paths = reg.watchedRootPaths
        guard !paths.isEmpty else {
            folderWatcher.stop()
            return
        }
        folderWatcher.onNewFiles = { incoming in
            Task { @MainActor in
                let dedup = Array(Set(incoming.map(\.standardizedFileURL)))
                guard !dedup.isEmpty else { return }
                let outcome = await DownloadsSortOrchestrator.shared.sort(files: dedup, prefs: prefs)
                guard outcome.hasWork else { return }
                vm.deliverCompletedSort(outcome, prefs: prefs)
            }
        }
        folderWatcher.start(paths: paths)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var collected: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var resolved: URL?
                if let url = item as? URL { resolved = url }
                else if let url = item as? NSURL { resolved = url as URL }
                else if let data = item as? Data { resolved = URL(dataRepresentation: data, relativeTo: nil) }
                guard let url = resolved else { return }
                lock.lock()
                collected.append(url)
                lock.unlock()
            }
        }
        group.notify(queue: .main) {
            guard !collected.isEmpty else { return }
            Task {
                await runSortWork { await vm.sortIncomingFiles(collected, prefs: prefs) }
            }
        }
        return true
    }
}
