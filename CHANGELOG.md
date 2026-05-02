# Changelog

## Unreleased

_(Nothing yet.)_

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
