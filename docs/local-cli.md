# Binky CLI (`binky`)

Terminal access to **the same Organizer prefs and sort engine as Binky**, without opening the GUI. Build from source in this repo (`Binky/` is the Xcode app; `BinkyCore/` ships the standalone binary).

```bash
cd BinkyCore
swift build -c release
# → .build/release/binky
```

Add that path to `$PATH`, or symlink it somewhere like `~/bin/binky`.

## What it respects

- `UserDefaults` keys Binky persists for routing rules, Finder tags, Routines (saved presets), duplicate mode, exclusions, Downloads root, and bookmarks (`WatchFolderPathResolver` when bookmarks resolve — see Sandbox).
- Stable-file waits, collisions, tagging (when tagging is enabled in Settings), hashes, receipts, OCR-driven rules — same Swift package as `Binky.app`.
- Cooperative lock on `~/Library/Application Support/Binky/sort.lock`: if **Binky** or **`binky sort`** holds it, another sort exits **`1`**.

## Sandbox / bookmarks

Terminal is **not** sandboxed, but **security-scoped bookmarks from the GUI do not attach to the Terminal**. Prefer absolute paths (`~/Downloads/foo.pdf`). Routine watch folders rely on bookmarks plus stored POSIX strings; resolution errors surface as stderr hints.

## Global conventions

1. Paths may include **`"-"`**, meaning “read POSIX paths from stdin (one path per line)”.
2. **`--json`** prints a single schema-tagged envelope on stdout. Human chatter goes to **stderr**.
3. **`--quiet`** / **`-q`** suppresses stderr progress for long batches.
4. Flags can appear **before or after** positional arguments (`routines run Calm Desk --json` works).
5. Exit **`0`** on success; **`1`** on parse/runtime failure, lock contention, undo move failures.

## Commands

### `sort`

Writes moves and appends history rows just like GUI sorts (`binky undo` reads the same payloads).

```bash
binky sort --root ~/Desktop/Inbox ~/Desktop/Inbox/paper.pdf -
binky sort --quiet ~/Downloads/export.zip
```

- **`--root <dir>`** — inbox root pinned for every URL this invocation (`rootOverride`).
- **`--dry-run`** — emits preview semantics (**no moves**) with a stderr note.

JSON schema: **`binky.sort.outcome/1.0.0`** (wraps `SortBatchOutcome`).

### `preview`

Read-only rows from `SortPreviewPlanner`.

```bash
find ~/Downloads -maxdepth 1 -mtime -2 -type f | binky preview --json -
```

JSON schema: **`binky.sort.preview/1.0.0`** (`entries[]` with `input`, `plannedDestination`, `category`, `matchedRule`, `addedTags`, `disposition`).

### `undo`

Replays stored `SortBatchOutcome` blobs backwards over reversible `(destination → source)` pairs.

```bash
binky undo
binky undo --batch 6F63D3D4-E4C2-4175-9026-ABCDEF123456 --json
```

Defaults to newest history slice. Schema **`binky.sort.undo/1.0.0`**.

### `routines`

```bash
binky routines list --json
binky routines run "Calm Desktop"
```

`list`: schema **`binky.routines.list/1.0.0`**.  
`run`: sweeps the routine’s inbox (`SortSweepFilesCollection`) under the flock, persists history.

`run --json`: schema **`binky.routines.run.outcome/1.0.0`** (includes `routineName`).

`automations …` redirects to **`routines`** while printing **`warning:`** deprecation text.

### `tag`

Computes tags (same precedence as sorting) **and merges** Finder xattrs via `FinderTagApplicator`.

Requires **Assign Finder tags when sorting** toggled ON in Settings.

Schema **`binky.tag.apply/1.0.0`**.

## Prefs coherence

`BinkyPrefsStore.appendSortOutcomeRecord` invokes `defaults.synchronize()` after writing `sessionHistoryData` so the CLI sees fresh history while the GUI is open — still prefer not to fight concurrent writers.

## Version constant

Bump `BinkyCLIPackageMeta.version` in `BinkyCore/Sources/BinkyCLILib/BinkyCLIPackageMeta.swift` next to README / marketing bumps.
