import SwiftUI

enum MainWindowMode: String, CaseIterable {
    case quickSort
    case routines

    var title: String {
        switch self {
        case .quickSort:
            return String(localized: "Quick Sort", comment: "Main window mode segmented control.")
        case .routines:
            return String(localized: "Routines", comment: "Main window mode segmented control.")
        }
    }
}

enum MainWindowModeVisibility: String, CaseIterable, Identifiable {
    case quickSortOnly
    case routinesOnly
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickSortOnly:
            return String(localized: "Quick Sort only", comment: "Settings: show only Quick Sort main layout.")
        case .routinesOnly:
            return String(localized: "Routines only", comment: "Settings: show only Routines main layout.")
        case .both:
            return String(localized: "Quick Sort and Routines", comment: "Settings: allow switching between both main layouts.")
        }
    }

    var allowsQuickSort: Bool { self != .routinesOnly }
    var allowsRoutines: Bool { self != .quickSortOnly }
}

struct MainWindowModeSwitcher: View {
    @Binding var mainWindowStored: String

    var body: some View {
        Picker(selection: $mainWindowStored) {
            ForEach(MainWindowMode.allCases, id: \.rawValue) { mode in
                Text(mode.title).tag(mode.rawValue)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(String(localized: "Main layout", comment: "Segmented picker: Quick Sort vs Routines."))
    }
}
