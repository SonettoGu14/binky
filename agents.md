# Agent notes — Binky (macOS)

Use this alongside `CLAUDE.md`. It records **product and UI conventions** so changes stay consistent.

## Apple design language (macOS Settings–style UI)

- **Segmented controls** (`Picker` + `.pickerStyle(.segmented)`): Use for **2–5 mutually exclusive panes** in a single settings surface (e.g. Image / Video / PDF under Presets). This matches System Settings patterns and avoids long vertical scrolling for parallel option groups.
- **Settings window navigation**: Host preferences in a dedicated **`Window`** scene with **`windowToolbarStyle(.unified(showsTitle: true))`** (same pattern as Dinky — not the SwiftUI **`Settings`** scene, which splits the navigation chrome). Inside, use **`NavigationSplitView`** with a sidebar **`List`** (grouped sections: General, Sorting, Interface). The detail column uses **`NavigationStack`** with per-pane titles and optional back/forward history (see ``PreferencesView``).
- **Grouped `Form`**: Use section **headers** to name groups; use **footers** sparingly for secondary explanation (progressive disclosure). Prefer concise captions over long instructional blocks.
- **Accessibility**: If `.labelsHidden()` is used on a control for layout, set `.accessibilityLabel` (and related inputs when needed) so VoiceOver still describes the control.
- **Hierarchy**: Place the control that **changes scope** (segmented picker) **above** the content it affects, with a clear section header (e.g. “Media”).
- **Cross-cutting settings**: If an option affects multiple panes (e.g. Smart quality and PDF/video tiers), keep it in a **dedicated section above** the segmented control so it stays visible when switching panes.

## App constraints

- See `CLAUDE.md` for bundle size and dependency rules.
