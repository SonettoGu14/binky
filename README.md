# Binky

**Binky Free keeps Downloads tidy.** A native macOS app that watches your inbox (defaults to `~/Downloads`), waits for files to finish downloading, then sorts them into sensible buckets — Images, PDFs, Media, Documents, Archives, Apps, Screenshots, Misc — with unknowns routed to **Review** so nothing sketchy silently disappears. Optional Finder tags; move/review summaries and session history with reveal / undo where possible.

**Binky Plus / Smart** (copy only in this repo) is the planned tier for automatic hands-off sorting — not implemented in v1.

- **Site & support:** [binkyfiles.com](https://binkyfiles.com)
- **Repo:** [github.com/heyderekj/binky](https://github.com/heyderekj/binky)

## Features (v1 organizer)

- **Sort Downloads Now** — primary action; stable-file gate, collision-safe moves
- **Profiles & sorting rules** — destination behavior per profile; routing preview language in-app
- **Watch inbox** — defaults on; falls back to `~/Downloads` when a bookmark is missing
- **Finder Quick Action / Services** — “Sort with Binky” on selected files
- **Shortcuts** — “Sort Files” App Intent hands paths to the running app
- **Review bucket** — ambiguous / unknown extensions land here first
- **History** — batch summaries using `SortBatchOutcome` payloads (moved / skipped / review counts)
- **Launch at login** — optional (Login Items)
- **Small native stack** — SwiftUI + AppKit; see `CLAUDE.md` for dependency rules

Compression-era tooling may still ship in the bundle for compatibility; the **shipping UX is organizer-first**.

## Install

**Homebrew (custom tap in this repo):**

```bash
brew tap heyderekj/binky https://github.com/heyderekj/binky
brew install --cask binky
```

See [Casks/README.md](Casks/README.md). Release automation refreshes `Casks/binky.rb` via `./release.sh`.

**Manual:** Download **`Binky-{version}.dmg`** or **`Binky-{version}.zip`** from [GitHub Releases](https://github.com/heyderekj/binky/releases) and drag **`Binky.app`** to Applications.

## Development

Open **`Binky.xcodeproj`** in Xcode (scheme **Binky**). Run tests:

```bash
xcodebuild -scheme Binky -configuration Debug test -destination 'platform=macOS'
```

## About the developer

Hey! I'm [Derek Castelli](https://www.heyderekj.com), a full-time freelance web designer (Webflow/Figma). Binky grew out of needing a **trust-first** Downloads workflow — sorting and visibility first, automation later.
