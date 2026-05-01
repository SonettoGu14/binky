import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Main window: slim Binky behavior sidebar + recent sort activity (not a compression dropzone).
struct OrganizerMainView: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @EnvironmentObject var updater: UpdateChecker
    @ObservedObject var vm: OrganizerViewModel
    @ObservedObject private var sortProgress = SortProgressTracker.shared
    @ObservedObject private var diagnostics = DiagnosticsReporter.shared

    @State private var isDropTargeted = false
    @State private var showingHistorySheet = false
    @State private var showingCurrentlySortingSheet = false
    @State private var showingSortPreview = false
    @State private var sortPreviewRows: [SortPreviewEntry] = []

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
            BinkyMenuBarController.shared.refresh()
        }
        .onChange(of: prefs.showMenuBarIcon) { _, _ in
            BinkyMenuBarController.shared.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .binkyShowHistory)) { _ in
            showingHistorySheet = true
        }
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
        .sheet(isPresented: $showingCurrentlySortingSheet) {
            CurrentlySortingSheet()
        }
        .sheet(isPresented: $showingSortPreview) {
            SortPreviewSheet(rows: sortPreviewRows)
        }
        .sheet(item: $vm.pendingSortOutcome) { outcome in
            SortOutcomeSheet(
                outcome: outcome,
                onUndo: { vm.applySortOutcomeDismissalDefaults() },
                onDismiss: { vm.applySortOutcomeDismissalDefaults() },
                onTransientStatus: { vm.flashTransientStatus($0) }
            )
            .id(sortOutcomeSheetRefreshID(for: outcome))
        }
        .sheet(item: $diagnostics.pendingCrashReport) { report in
            PostCrashReportSheet(report: report, diagnostics: diagnostics)
        }
        .onReceive(NotificationCenter.default.publisher(for: .binkyPrepareQuit)) { _ in
            vm.pendingSortOutcome = nil
            diagnostics.pendingCrashReport = nil
            showingHistorySheet = false
            showingSortPreview = false
            showingCurrentlySortingSheet = false
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

                inboxControlsCard

                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionHeading(
                        icon: "slider.horizontal.3",
                        title: String(localized: "Settings", comment: "Organizer sidebar settings header.")
                    )

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

                    Toggle(String(localized: "Open watch folder in Finder when done", comment: "Settings UI."), isOn: Binding(
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
                        title: String(localized: "Profiles", comment: "Organizer sidebar shortcut to profiles tab."),
                        systemImage: "slider.horizontal.3"
                    )
                    organizerSettingsSidebarLink(
                        tab: .watch,
                        title: String(localized: "Watch Folder", comment: "Organizer sidebar shortcut to watch tab."),
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
            ForEach(prefs.savedPresets) { preset in
                profileSelectionRow(
                    name: preset.name,
                    subtitle: preset.organizerListSubtitle,
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
                    .foregroundStyle(isActive ? binkyTintColor : Color.primary.opacity(0.25))

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
                    .fill(isActive ? binkyTintColor.opacity(0.08) : Color.clear)
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
        .foregroundStyle(binkyTintColor)
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
        .foregroundStyle(binkyTintColor)
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

    private var sortProgressBanner: some View {
        Group {
            if sortProgress.isActive {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Sorting", comment: "Main pane banner title while inbox sort runs."))
                                .font(.subheadline.weight(.semibold))
                            if sortProgress.bannerCaption.isEmpty == false {
                                Text(sortProgress.bannerCaption)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .accessibilityLabel(sortProgress.bannerCaption)
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            Button {
                                if sortProgress.runState == .paused {
                                    DownloadsSortOrchestrator.shared.resumeCurrentSort()
                                } else {
                                    DownloadsSortOrchestrator.shared.pauseCurrentSort()
                                }
                            } label: {
                                Image(systemName: sortProgress.runState == .paused ? "play.fill" : "pause.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(binkyTintColor.opacity(sortProgress.runState == .stopping ? 0.5 : 0.9))
                            .accessibilityLabel(
                                sortProgress.runState == .paused
                                    ? String(localized: "Resume sort", comment: "Main banner button to resume paused sort.")
                                    : String(localized: "Pause sort", comment: "Main banner button to pause active sort.")
                            )
                            .disabled(sortProgress.runState == .stopping)

                            Button {
                                DownloadsSortOrchestrator.shared.stopCurrentSort()
                            } label: {
                                Image(systemName: "stop.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red.opacity(sortProgress.runState == .stopping ? 0.4 : 0.8))
                            .accessibilityLabel(String(localized: "Stop sort", comment: "Main banner button to stop active sort."))
                            .disabled(sortProgress.runState == .stopping)
                        }
                        Button {
                            showingCurrentlySortingSheet = true
                        } label: {
                            Image(systemName: "chevron.down.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: 24))
                                .foregroundStyle(binkyTintColor.opacity(0.85))
                                .accessibilityLabel(String(localized: "Show sort details", comment: "Opens per-file sorting sheet."))
                                .accessibilityHint(String(localized: "Shows filenames and activity for this sort.", comment: "VoiceOver hint for sort details button."))
                        }
                        .buttonStyle(.plain)
                    }

                    BinkySortProgressBar(
                        fraction: sortProgress.fraction,
                        caption: nil,
                        compact: false,
                        showsCaption: false
                    )
                    .animation(.easeInOut(duration: 0.42), value: sortProgress.fraction)
                }
                .padding(.horizontal, 20)
                .padding(.top, showReviewBanner ? 10 : 16)
                .padding(.bottom, 14)
                .background(Color.primary.opacity(0.035))
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.22)
                }
            }
        }
    }

    private var activityMainPane: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                if showReviewBanner {
                    reviewBanner
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    Divider()
                        .opacity(0.35)
                }

                sortProgressBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.26), value: sortProgress.isActive)

                transientNoticeBanner

                activitySection
            }

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(binkyTintColor.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
    }

    private var inboxControlsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                settingsSectionHeading(
                    icon: "tray.full",
                    title: String(localized: "Watch Folder", comment: "Organizer sidebar watch folder controls title.")
                )

                Spacer(minLength: 0)

                if prefs.folderWatchEnabled {
                    Button {
                        prefs.folderWatchPaused.toggle()
                    } label: {
                        Image(systemName: prefs.folderWatchPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 14, height: 14)
                            .padding(5)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(prefs.folderWatchPaused ? .green : binkyTintColor)
                    .accessibilityLabel(
                        prefs.folderWatchPaused
                            ? String(localized: "Resume auto-sort", comment: "Play icon button that resumes auto-sort.")
                            : String(localized: "Pause auto-sort", comment: "Pause icon button that pauses auto-sort.")
                    )
                    .accessibilityHint(
                        prefs.folderWatchPaused
                            ? String(localized: "Resumes reacting to new files in the inbox.", comment: "VoiceOver hint for resuming auto-sort.")
                            : String(localized: "Temporarily stops reacting to new files in the inbox.", comment: "VoiceOver hint for pausing auto-sort.")
                    )
                }
            }

            HStack(alignment: .center, spacing: 8) {
                Button {
                    openInboxInFinder()
                } label: {
                    Text(watchedInboxPath)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(binkyTintColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Show in Finder", comment: "Reveal watched inbox in Finder."))
                .accessibilityHint(String(localized: "Opens the watched folder in a Finder window.", comment: "VoiceOver hint for watch path button."))

                if prefs.folderWatchEnabled {
                    Button(String(localized: "Choose…", comment: "Watch folder chooser button.")) {
                        pickGlobalWatchFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                Toggle(String(localized: "Watch", comment: "Short watch toggle in organizer sidebar inbox card."), isOn: Binding(
                    get: { prefs.folderWatchEnabled },
                    set: { prefs.folderWatchEnabled = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11, weight: .medium))

                Spacer(minLength: 0)

                if sortProgress.isActive {
                    BinkySortProgressBar(
                        fraction: sortProgress.fraction,
                        caption: nil,
                        compact: true,
                        showsCaption: false
                    )
                    .frame(maxWidth: 140)
                    .transition(.opacity)
                }
            }

            if prefs.folderWatchEnabled {
                if prefs.folderWatchPaused {
                    Text(String(localized: "Watching is on, but new files won’t sort until you resume.", comment: "Shown when auto-sort is paused."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    sortPreviewRows = vm.inboxPreviewEntries(prefs: prefs)
                    showingSortPreview = true
                } label: {
                    Text(String(localized: "Preview…", comment: "Dry-run sort sorted folders."))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)

                Button {
                    Task { await vm.runInteractiveDownloadsSweep(prefs: prefs) }
                } label: {
                    Text(String(localized: "Sort Now", comment: "Primary sort button."))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.03)))
    }

    private var transientNoticeBanner: some View {
        Group {
            if let msg = vm.transientBannerMessage, !sortProgress.isActive {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "ellipsis.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.transientBannerMessage)
    }

    private var watchedInboxPath: String {
        prefs.activeSortSweepRootDirectory().path
    }

    private var reviewBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Pending review", comment: "Organizer banner when the Review folder has items."))
                    .font(.subheadline.weight(.semibold))
                Text(
                    String(localized: "\(reviewBannerCount) want a second look.", comment: "Organizer banner: files in Review needing attention; integer count interpolated.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(String(localized: "Open Review in Finder", comment: "Reveal Review folder in Finder.")) {
                openReviewInFinder()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.primary)
            .tint(.white.opacity(0.32))
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
                HStack(spacing: 12) {
                    Text(String(localized: "Recent activity", comment: "Organizer main section title."))
                        .font(.headline)
                    Spacer(minLength: 0)
                    Button(S.clear) {
                        clearRecentActivity()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(binkyTintColor)
                    .font(.subheadline.weight(.medium))
                    .accessibilityHint(String(localized: "Clears recent activity and returns to the empty state.", comment: "VoiceOver hint for clearing recent activity."))
                }
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

                Button(String(localized: "Show in Finder", comment: "Reveal watched inbox in Finder.")) {
                    openInboxInFinder()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(binkyTintColor)
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
        let root = prefs.activeSortSweepRootDirectory()
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

    private func sortOutcomeSheetRefreshID(for outcome: SortBatchOutcome) -> String {
        outcome.id.uuidString
    }

    // MARK: - Actions

    private func openInboxInFinder() {
        let root = prefs.activeSortSweepRootDirectory()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root.path)
    }

    private func openReviewInFinder() {
        let root = prefs.activeSortSweepRootDirectory()
        let reviewURL = root.appendingPathComponent(FileSortCategory.review.downloadsSubfolder, isDirectory: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: reviewURL.path)
    }

    private func clearRecentActivity() {
        prefs.sessionHistory = []
        vm.lastSortOutcome = nil
        vm.pendingSortOutcome = nil
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
                await vm.sortIncomingFiles(collected, prefs: prefs)
            }
        }
        return true
    }
}
