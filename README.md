# Binky

A native macOS app that calms a fussy Downloads folder. Binky watches your inbox (defaults to `~/Downloads`), waits for files to finish downloading, then routes them into clear destination folders — Images, PDFs, Media, Documents, Archives, Apps, Screenshots, and Misc.

Unknown or sketchy extensions do not disappear silently: they land in **Review** first. Optional Finder tags, move summaries, and session history make it easy to verify what happened and undo where possible.

**Requires macOS 14 Sonoma or later** (Liquid Glass UI on macOS 26 Tahoe).

## Releases

**1.x** is organizer-first: sort now, watch continuously, review uncertain files, and keep a reliable history of move outcomes.

**Homebrew:** add this repo as a tap once, then install the cask (see [Casks/README.md](Casks/README.md) for why it lives in-tree):

```bash
brew tap heyderekj/binky https://github.com/heyderekj/binky
brew install --cask binky
```

You can also download `Binky-{version}.dmg` or `Binky-{version}.zip` from [GitHub Releases](https://github.com/heyderekj/binky/releases).

## About the developer

Hey! I'm [Derek Castelli](https://www.heyderekj.com), a full-time freelance web designer working primarily in Webflow and Figma. Binky came from a boring problem: Downloads gets noisy fast, and manually dragging files around all day is not the dream.

## Features

- **Sort Downloads Now** - one-click sort with stable-file checks and collision-safe moves
- **Watch folder** - monitor Downloads continuously and route new files as they settle
- **Profiles and rules** - define destination behavior per profile with predictable routing
- **Review folder** — unknown or ambiguous extensions get held for inspection first
- **History and undo-friendly flow** - batch summaries with moved, skipped, and review counts
- **Finder Quick Action and Services** - run "Sort with Binky" on selected files
- **Apple Shortcuts support** - "Sort Files" App Intent can hand paths to Binky
- **Finder tags (optional)** - apply tags during routing for quick visual scanning
- **Launch at login** - keep it ready in the background when your Mac boots
- **Native macOS stack** - SwiftUI + AppKit, no bundled web runtime

## Screenshots

**Sorting dashboard**

![Binky sorting dashboard](site/screenshots/sorting.png)

**Profiles and routing**

![Binky profiles and rules](site/screenshots/profiles.webp)

**Sort breakdown**

![Binky sorting breakdown](site/screenshots/sorting-breakdown.webp)

**Review queue**

![Binky review queue](site/screenshots/review.webp)

## What others don't do

- **Treat uncertainty safely** - questionable files go to **Review** instead of being buried in the wrong folder
- **Sort with context, not just extension lists** - profiles and routing logic keep behavior consistent across different workflows
- **Keep a readable paper trail** - clear per-batch outcomes so you can verify what moved and what did not
- **Fit native Mac workflows** - Finder Services, Shortcuts, and login-item support out of the box
- **Stay lightweight** - organizer-first UX on Apple frameworks with strict bundle-size discipline

## Why it exists

Downloads is where good naming conventions go to die. Binky exists to make that mess quiet again without adding another noisy "productivity system."

Fussy inbox. Meet Binky.

## How it works

Binky is built in Swift and SwiftUI with AppKit integration for Mac-native behavior. The organizer pipeline waits for files to stabilize, classifies by routing rules, then moves them safely to target destination folders with review safeguards.

The app keeps session outcomes so you can see exactly what happened in each run. Optional compatibility code from earlier compression-focused iterations may remain in the bundle, but the shipping product and UX are organizer-led.

## Built with

- SwiftUI
- AppKit
- Foundation
- UserNotifications
- Xcode project + native macOS frameworks only

## Install

Download the latest release and drag `Binky.app` to Applications.

Or install with Homebrew:

```bash
brew tap heyderekj/binky https://github.com/heyderekj/binky
brew install --cask binky
```

For local development:

```bash
xcodebuild -scheme Binky -configuration Debug test -destination 'platform=macOS'
```
