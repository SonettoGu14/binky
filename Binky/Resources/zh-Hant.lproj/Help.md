# Binky Help

Binky keeps your **Downloads inbox** tidy: it watches for finished files, moves them into sensible folders, optionally adds Finder tags, and shows clear **summary + history** so you always know what happened.

## Quick start

1. Leave **Watch this folder** on (defaults to your Downloads inbox).
2. Drop files into that folder. Binky waits until downloads look **stable**, then sorts them.
3. Use **Sort Downloads Now** (`{{SK_SORT_NOW}}`) any time to sweep everything sitting at the top level of the inbox.

Optional: After a sort, use **Send to Dinky** on the summary sheet (or **Watch in Dinky** on a destination folder) to hand off images, PDFs, and videos to [Dinky](https://dinkyapp.com) for compression, or set Dinky to watch those folders so future drops are slimmed automatically.

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
| Sort Downloads Now | `{{SK_SORT_NOW}}` |
| Settings | `{{SK_SETTINGS}}` |
| Binky Help | `{{SK_HELP}}` |
| Last Sort Summary… | `{{SK_LAST_SORT}}` |

## Finder & Services

**Sort with Binky** appears in Finder **Services** (and as a **Quick Action**). Turn it on under **System Settings -> Keyboard -> Keyboard Shortcuts -> Services**.

- **Folders:** Right-click a folder and choose **Sort with Binky**. Binky treats that folder as a one-shot inbox. It sorts the **files at the top level** into the usual subfolders (`Images`, `Documents`, etc.) **inside** the folder you picked. Nested subfolders are left alone.
- **Single files:** Same routing rules as the main window, but the file has to live **inside** the inbox you are watching. Anything outside that inbox is ignored.

Dropping **folders** or **files** onto Binky's **Dock icon** follows the same rules.

## Menu bar mode

In **Settings -> Appearance**, keep **Show menu bar icon** on for quick access even when the window is closed.

- Turn on **Menu bar only (hide Dock icon)** if you want Binky to run from the menu bar.
- The menu bar lets you run **Sort Now**, pause/resume watching, open **History**, and jump to **Settings**.
- Watching continues while Binky is running in menu bar mode.

## History & undo

Every sort run is saved in **History** (`App menu -> History…`).

- Use **Open Summary…** on a history row to reopen that run's move/review summary.
- In a summary sheet, use **Undo moves** to put files from that run back where they were.
- Use **Last Sort Summary…** (`{{SK_LAST_SORT}}`) to reopen the most recent summary quickly.

## Shortcuts app

Binky exposes a **Sort files** intent so you can automate sorting from the Shortcuts app, using the same routing rules as the main window.

## Privacy

Nothing leaves your Mac unless **you** choose to send diagnostics from the crash reporter or open a feedback email. Learn more at **binkyfiles.com**.
