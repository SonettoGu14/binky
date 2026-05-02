# Changelog

## Unreleased

### Novel features roadmap (phases 1–7)

- **Source-aware routing**: `kMDItemWhereFroms` → rule `originDomains`, `{origin}` rename token, history/origin chips for Review.
- **Duplicates**: `FileHashStore` (SHA-256 + image dHash), duplicate disposition and prefs.
- **Smart sorting**: `ContentInspector` (Vision + PDFKit), screenshot OCR rename, receipt heuristics, `{ocr}` / `{vendor}` / `{amount}` tokens.
- **Aging**: per-category rules in Settings, daily sweep via `FileAgingService`.
- **Digest**: rolling stats + daily notification via `SortDigestScheduler`.
- **NL rules**: `RuleSynthesizer` (heuristics + Foundation Models on macOS 26 when available), Settings composer.
- **Tests**: `WhereFromsTests`, classification coverage for new categories.

### Fixes

- **Xcode**: restored missing `PBXFileReference` / `PBXBuildFile` entries for `FolderWatcher.swift` and `WatchRegistry.swift` so watch-folder types compile.
- **Debug builds**: `SWIFT_COMPILATION_MODE = wholemodule` on the project Debug configuration to avoid incremental emit-module failures.
