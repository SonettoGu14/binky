import AppIntents
import AppKit
import Foundation

/// Shortcuts / Siri integration: hand files to the running app for inbox sorting.
struct SortFilesWithBinkyIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "Sort Files",
        comment: "Shortcuts: intent title."
    )

    static var description = IntentDescription(
        LocalizedStringResource(
            "Sorts files with Binky using your watch folder routing rules.",
            comment: "Shortcuts: intent description."
        )
    )

    static var openAppWhenRun: Bool = true

    @Parameter(
        title: LocalizedStringResource("Files", comment: "Shortcuts: files parameter."),
        description: LocalizedStringResource("Files to sort into your watch folder destinations.", comment: "")
    )
    var files: [IntentFile]

    static var parameterSummary: some ParameterSummary {
        Summary("Sort \(\.$files) with Binky")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let urls = files.map { URL(fileURLWithPath: $0.filename) }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .binkyOpenFiles, object: urls)
        return .result()
    }
}
