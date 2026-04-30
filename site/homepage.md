# Binky

**Tagline:** Quiets your Downloads.

A native macOS app that watches your inbox (defaults to `~/Downloads`), waits for files to finish landing, then sorts them into sensible buckets — Images, PDFs, Media, Documents, Archives, Apps, Screenshots, Misc. Unknowns route to **Review** so nothing sketchy silently disappears. Optional Finder tags; history with reveal and undo where macOS allows.

- **Site:** [binkyfiles.com](https://binkyfiles.com)
- **Repo:** [GitHub — heyderekj/binky](https://github.com/heyderekj/binky)
- **Support:** [help@binkyfiles.com](mailto:help@binkyfiles.com)
- **Version line:** Requires macOS 14 Sonoma or later · Free during beta · Open source (MIT)

## Highlights

- **Sort Downloads Now** — primary action; stable-file gate, collision-safe moves
- **Profiles & sorting rules** — destination behavior per profile
- **Watch inbox** — optional; defaults to Downloads when a bookmark is missing
- **Finder Quick Action** — “Sort with Binky” on selected files
- **Shortcuts** — “Sort Files” App Intent passes paths to the running app
- **Review bucket** — ambiguous types land here first
- **History** — batch summaries; undo where possible

## Install

**GitHub:** Latest release and DMG/ZIP: [github.com/heyderekj/binky/releases/latest](https://github.com/heyderekj/binky/releases/latest)

**Homebrew:**

```bash
brew tap heyderekj/binky https://github.com/heyderekj/binky
brew install --cask binky
```

**Gatekeeper:** if macOS blocks the first launch, **System Settings → Privacy & Security → Open Anyway**, or:

```bash
xattr -dr com.apple.quarantine /Applications/Binky.app
```

## More

Machine-readable site summary: [llms.txt](https://binkyfiles.com/llms.txt)

© Testament Made, LLC
