import Foundation

/// Organizer profile (per-preset watch folder, tags, routing rules). Renamed conceptually from Dinky-era “preset”; kept as ``CompressionPreset`` for ``UserDefaults`` compatibility.
struct CompressionPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String

    var watchFolderEnabled: Bool
    var watchFolderModeRaw: String
    var watchFolderPath: String
    var watchFolderBookmark: Data

    var customFinderTags: [String]
    var inboxSortRules: [InboxSortRule]
    var newTagExpiryDays: Int
    var postSortShortcutName: String

    let createdAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.watchFolderEnabled = false
        self.watchFolderModeRaw = "global"
        self.watchFolderPath = ""
        self.watchFolderBookmark = Data()
        self.customFinderTags = []
        self.inboxSortRules = []
        self.newTagExpiryDays = 0
        self.postSortShortcutName = ""
        self.createdAt = .now
    }

    init(duplicating source: CompressionPreset, name: String) {
        self.id = UUID()
        self.name = name
        self.watchFolderEnabled = source.watchFolderEnabled
        self.watchFolderModeRaw = source.watchFolderModeRaw
        self.watchFolderPath = source.watchFolderPath
        self.watchFolderBookmark = source.watchFolderBookmark
        self.customFinderTags = source.customFinderTags
        self.inboxSortRules = source.inboxSortRules
        self.newTagExpiryDays = source.newTagExpiryDays
        self.postSortShortcutName = source.postSortShortcutName
        self.createdAt = .now
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now

        watchFolderEnabled = try c.decodeIfPresent(Bool.self, forKey: .watchFolderEnabled) ?? false
        let rawMode = try c.decodeIfPresent(String.self, forKey: .watchFolderModeRaw) ?? "global"
        watchFolderModeRaw = (rawMode == "destination") ? "global" : rawMode
        watchFolderPath = try c.decodeIfPresent(String.self, forKey: .watchFolderPath) ?? ""
        watchFolderBookmark = try c.decodeIfPresent(Data.self, forKey: .watchFolderBookmark) ?? Data()

        customFinderTags = try c.decodeIfPresent([String].self, forKey: .customFinderTags) ?? []
        inboxSortRules = try c.decodeIfPresent([InboxSortRule].self, forKey: .inboxSortRules) ?? []
        newTagExpiryDays = try c.decodeIfPresent(Int.self, forKey: .newTagExpiryDays) ?? 0
        postSortShortcutName = try c.decodeIfPresent(String.self, forKey: .postSortShortcutName) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt
        case watchFolderEnabled, watchFolderModeRaw, watchFolderPath, watchFolderBookmark
        case customFinderTags, inboxSortRules, newTagExpiryDays, postSortShortcutName
    }

    /// Finder-style unique profile name among existing names.
    static func uniqueDuplicatePresetName(baseName: String, existingNames: Set<String>) -> String {
        let copyFrag = String(localized: " copy", comment: "Filename: first duplicate after base name, as in Finder “file copy”.")
        var n = 1
        while true {
            let candidate: String
            if n == 1 {
                candidate = baseName + copyFrag
            } else {
                candidate = baseName + copyFrag + " \(n)"
            }
            if !existingNames.contains(candidate) { return candidate }
            n += 1
        }
    }

    /// Short subtitle for profile lists (sidebar, Settings).
    var organizerListSubtitle: String {
        var parts: [String] = []

        if watchFolderEnabled {
            if watchFolderModeRaw == "unique" {
                if watchFolderPath.isEmpty {
                    parts.append(String(localized: "Unique folder (not set)", comment: "Profile subtitle: unique watch folder not chosen."))
                } else {
                    parts.append(URL(fileURLWithPath: watchFolderPath).lastPathComponent)
                }
            } else {
                parts.append(String(localized: "Global watch", comment: "Profile subtitle: uses global watch folder."))
            }
        } else {
            parts.append(String(localized: "Watch off", comment: "Profile subtitle: watch disabled."))
        }

        let tagCount = customFinderTags.count
        if tagCount == 1 {
            parts.append(String(localized: "1 tag", comment: "Profile subtitle: single custom tag."))
        } else if tagCount > 1 {
            parts.append(String.localizedStringWithFormat(
                String(localized: "%lld tags", comment: "Profile subtitle: multiple custom tags."),
                Int64(tagCount)
            ))
        }

        let ruleCount = inboxSortRules.count
        if ruleCount == 1 {
            parts.append(String(localized: "1 rule", comment: "Profile subtitle: single sort rule."))
        } else if ruleCount > 1 {
            parts.append(String.localizedStringWithFormat(
                String(localized: "%lld rules", comment: "Profile subtitle: multiple sort rules."),
                Int64(ruleCount)
            ))
        }

        if newTagExpiryDays > 0 {
            parts.append(String.localizedStringWithFormat(
                String(localized: "%lldd \u{201C}New\u{201D}", comment: "Profile subtitle: New-tag expiry in days."),
                Int64(newTagExpiryDays)
            ))
        }

        let trimmedShortcut = postSortShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedShortcut.isEmpty {
            parts.append("→ \(trimmedShortcut)")
        }

        if parts.isEmpty {
            return String(localized: "Default routing", comment: "Profile subtitle when no overrides set.")
        }
        return parts.joined(separator: " · ")
    }
}
