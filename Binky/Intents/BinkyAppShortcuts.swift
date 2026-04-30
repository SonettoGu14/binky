import AppIntents

/// Surfaces Binky’s Shortcuts actions in the Shortcuts app’s suggestions.
struct BinkyAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SortFilesWithBinkyIntent(),
            phrases: [
                "Sort files with \(.applicationName)",
                "Organize downloads with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("Sort Files", comment: "Shortcuts: suggested action short title."),
            systemImageName: "folder"
        )
    }
}
