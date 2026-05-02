import SwiftUI

/// Dry-run list of where inbox files would land — nothing is moved.
struct SortPreviewSheet: View {
    let rows: [SortPreviewEntry]
    var onDismiss: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Preview sort", comment: "Sort preview sheet title."))
                .font(.title2)

            Text(String(localized: "Nothing is moved yet. Incomplete downloads are treated as skipped.", comment: "Sort preview disclaimer."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Table(rows) {
                TableColumn(String(localized: "File", comment: "Sort preview table.")) { row in
                    Text(row.sourceLastPathComponent)
                        .lineLimit(1)
                }
                .width(min: 140, ideal: 180)

                TableColumn(String(localized: "Would move to", comment: "Sort preview table.")) { row in
                    Text(row.proposedDestinationPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .width(min: 180, ideal: 260)

                TableColumn(String(localized: "Why", comment: "Sort preview table: plain-language reason.")) { row in
                    Text(row.whyLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .width(min: 160, ideal: 220)

                TableColumn(String(localized: "Summary", comment: "Sort preview table.")) { row in
                    Text(row.summary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(minHeight: 220)

            HStack {
                Button(role: .cancel) {
                    onDismiss()
                    dismiss()
                } label: {
                    Text(String(localized: "Close", comment: "Dismiss preview sheet."))
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(22)
        .frame(minWidth: 720, minHeight: 360)
    }
}
