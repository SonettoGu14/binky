---
name: dinky-release-bump
description: Checklist for keeping Dinky release strings in sync across repo and site.
---

# Dinky — release string bump

Use **`./release.sh X.Y.Z --bump-only`** to sync `project.pbxproj` + site URLs in one step (no build/git). Full ship: **`./release.sh X.Y.Z`** (Release build, DMG, zip, commit, tag, `gh release create`).

When shipping a new **X.Y.Z** DMG to GitHub Releases, pinned references must match:

1. **site/index.html** — `<title>`, meta descriptions, JSON-LD `downloadUrl` / `softwareVersion`, download button `href`, visible version line.
2. **site/llms.txt** — “Download v…” link.
3. **site/homepage.md** — Download bullet and version line.
4. **site/compare/\*/index.html** — DMG `href` and visible `vX.Y · Requires` line on each SEO compare page (`release.sh` updates these automatically with the homepage).
5. **README.md** — if it embeds a specific DMG URL (optional; prefer `releases/latest` in prose when possible).

Search the repo for the **previous** version number to catch stragglers.
