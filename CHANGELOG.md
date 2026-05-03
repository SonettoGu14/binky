# Changelog

## Unreleased

### Added — v2.0 Automations

- **Automations** replace Profiles: each automation has its own source folder, enable toggle, rules, tag defaults, DMG install destination, and tag fan-out priority list. Multiple automations can run in parallel; the watch pipeline dedupes shared sources.
- **Global inbox + protected tags**: default watched folder plus **Protected Finder tags** (e.g. DoNotMove) so tagged files are never touched.
- **Rule upgrades**: match by Finder tag; forced **output extension** and `{newExt}` rename token; actions **Extract archive then trash**, **Install app from disk image**, **Sort into subfolder by Finder tag**.
- **Templates** when adding an automation (Downloads, Desktop, DMG install, archive extract, tag fan-out, screenshot archive, notes to Markdown, blank) plus empty-state onboarding for **Calm my Desktop**.
- **Services**: `ArchiveExtractionService` (ditto/tar), `DMGInstallerService` (hdiutil + copy `.app`), tag read for predicates/skip list.
- **Tests**: `AutomationsOverhaulTests` (tag predicate, fan-out priority, rename/`{newExt}`, zip extract, shared watch root routing).

### Changed

- Settings tabs: **Automations** merges the old Watch + Profiles surface; sidebar links and copy use Automation terminology.

## 1.2.0 — 2026-05-02

### Added

- **Sort performance**: skip stability polling for obviously settled files; bounded parallel pipeline; cheaper ContentInspector cache keys; image downsample before Vision OCR; reuse duplicate digest for inspection; energy throttle fast path on small batches; watch debounce with 1.5s max burst window.
- **Routing rules**: per-rule actions (move, Trash, rename in place, zip to destination); dry-run preview matches the live sort path; optional **Re-sort watched inboxes when rules change**.
- **Watch**: **Also watch inside immediate subfolders (one level)** for sweep, preview, and `topLevelInboxFiles`.
- **Organizer**: inline sort preview under the inbox card; clearer CTAs on the glass activity pane (prominent **Tidy here…** / **Open Summary…**).

### Fixed

- **Contrast**: Review banner and activity rows no longer use washed-out bordered buttons on `.ultraThinMaterial`.

## 1.1.1 — 2026-05-01

### Fixed

- **Homebrew cask**: `homepage` URL uses a trailing slash so `brew style --cask` passes CI.
- **Xcode / Swift 6**: cleared concurrency and cast warnings in `ContentInspector`, `DownloadSortServices`, and `FileAgingService` (no lock work inside async continuations; Vision results without a useless conditional cast; aging timer avoids capturing prefs in a `@Sendable` closure).
- **SwiftUI**: aging-rule “See what would go” preview loads rows on appear instead of publishing prefs changes during view updates.

## 1.1.0 — 2026-05-01

### Added

- **Source-aware routing**: read `kMDItemWhereFroms` for download origins; rule `originDomains`; `{origin}` rename token; origin hints on Review moves in history and activity.
- **Duplicates**: `FileHashStore` (SHA-256 + perceptual image hash), duplicate skip / Duplicates folder / Trash handling in prefs and sort pipeline.
- **Smart sorting**: `ContentInspector` (Vision + PDFKit) for OCR; optional smart screenshot names; receipt / invoice heuristics with auto-route to Receipts; `{ocr}`, `{vendor}`, `{amount}` rename tokens.
- **File aging**: per-category rules in Settings, daily sweep via `FileAgingService`, **See what would go** dry-run sheet.
- **Daily digest**: rolling counters + scheduled notification via `SortDigestScheduler`.
- **Natural-language rules**: `RuleSynthesizer` (phrase heuristics; Foundation Models on macOS 26 when available); **Here’s what Binky heard** preview before applying a generated rule.
- **Finder tags on sort**: `FinderTagComposer` for category defaults, profile overrides, and rule-level tag policy.
- **Voice & clarity**: `VOICE.md` copy reference; `SortVoiceCopy` for session stats, outcome “why” lines, activity chips (already had, receipts filed, in review); **Why** column on sort preview; **Review** triage sheet (move, make a rule, trash); duplicate **memory** count and **Forget everything** in General settings.
- **Tests**: `WhereFromsTests`, `FinderTagCompositionTests`, expanded classification tests.

### Fixed

- **Xcode**: restored missing `PBXFileReference` / `PBXBuildFile` entries for `FolderWatcher.swift` and `WatchRegistry.swift` so watch-folder types compile.
- **Debug builds**: `SWIFT_COMPILATION_MODE = wholemodule` on the project Debug configuration to avoid incremental emit-module failures.
