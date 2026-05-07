# Binky Help

Binky keeps your **watched folder** tidy: it watches for finished files, moves them into sensible folders, optionally adds Finder tags, and shows clear **summary + history** so you always know what happened.

## Quick start

1. Leave **Quick Sort** (default window) pointing at Downloads or drag in any fussy inbox. Hit **Sort Now**—no routine setup needed.
2. Drop files into that folder (or browse with Finder). Binky waits until downloads look **stable**, then sorts top-level items.
3. Use **Sort Now** (`{{SK_SORT_NOW}}`) anytime to sweep the active folder—or stay in Quick Sort mode for one-shot clears.

Want always-on calming? Switch the window to **Routines** (toolbar segment): each routine pairs a watched folder with its own sort rules.

Optional: After a sort, use **Send to Dinky** on the summary sheet (or **Watch in Dinky** on a sorted folder) to hand off images, PDFs, and videos to [Dinky](https://dinkyapp.com) for compression, or set Dinky to watch those folders so future drops are slimmed automatically.

## Where files go (starter profile)

| Kind | Folder |
| --- | --- |
| Images | Images |
| PDFs & documents | Documents |
| Video & audio | Media |
| Archives (zip, etc.) | Archives |
| Disk images / installers | Apps |
| Screenshots | Screenshots |
| Everything else Binky recognizes | Misc |
| Incomplete downloads / unknown types | Review |

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open Files… | `{{SK_OPEN_FILES}}` |
| Sort Now | `{{SK_SORT_NOW}}` |
| Settings | `{{SK_SETTINGS}}` |
| Binky Help | `{{SK_HELP}}` |
| Last Sort Summary… | `{{SK_LAST_SORT}}` |

## Finder & Services

**Sort with Binky** appears in Finder **Services** (and as a **Quick Action**). Turn it on under **System Settings → Keyboard → Keyboard Shortcuts → Services**.

- **Folders:** Right-click a folder and choose **Sort with Binky**. Binky treats that folder as a one-shot source folder. It sorts the **files at the top level** into the usual subfolders (`Images`, `Documents`, etc.) **inside** the folder you picked. Nested subfolders are left alone.
- **Single files:** Same routing rules as the main window, but the file has to live **inside** the watched folder. Anything outside that folder is ignored.

Dropping **folders** or **files** onto Binky's **Dock icon** follows the same rules.

## Routines

A **Routine** pairs a watched folder with its own set of sort rules and optional Finder tags.

- Add routines in **Settings → Routines** (gearshape.2 icon).
- Each routine watches its own folder independently. Rules in one routine don't affect other folders.
- With one routine enabled (and a resolved watch path), the menu bar shortcut runs **Sort Now** for that folder. With two or more, shortcuts become **Sort ▶**: pick **Sort All Folders** to sweep everything at once, or pick a specific routine name to sweep just that folder.

## Menu bar mode

In **Settings → Appearance**, keep **Show menu bar icon** on for quick access even when the window is closed.

- Turn on **Menu bar only (hide Dock icon)** if you want Binky to run from the menu bar.
- The menu bar lets you sort watched folders, pause/resume watching, open **History**, and jump to **Settings**.
- Watching continues while Binky is running in menu bar mode.

## History & undo

Every sort run is saved in **History** (`App menu → History…`).

- Use **Open Summary…** on a history row to reopen that run's move/review summary.
- In a summary sheet, use **Undo moves** to put files from that run back where they were.
- Use **Last Sort Summary…** (`{{SK_LAST_SORT}}`) to reopen the most recent summary quickly.

## Shortcuts app

Binky exposes a **Sort files** intent so you can chain sorting from the Shortcuts app, using the same routing rules as the main window.

## Open source

Source code is on [GitHub](https://github.com/heyderekj/binky) under the MIT license.

## Privacy

Nothing leaves your Mac unless **you** choose to send diagnostics from the crash reporter or open a feedback email. Learn more at **binkyfiles.com**.
