#!/bin/bash
# release.sh — build, package, and publish a new Binky release.
#
# Usage:
#   ./release.sh 1.2.3
#   ./release.sh 1.2.3 --bump-only   # steps 1–2 only (no build, git, or gh)
#
# What it does:
#   1. Bumps MARKETING_VERSION + CURRENT_PROJECT_VERSION in the Xcode project
#   2. Updates version + download URLs in site/index.html, site/llms.txt, site/homepage.md, site/compare/*/index.html
#   3. Builds the Release scheme
#   4. Creates the DMG (+ zip for in-app updater), then updates Casks/binky.rb (version + sha256 of the zip) for Homebrew
#   5. Commits, tags, pushes, and publishes the GitHub release
#
# Release notes: if a previous `v*` tag exists, notes use `git log $PREV_GIT_TAG..HEAD` (subjects
# only, chronological), excluding the “Bump to v$VERSION” commit. With **no** prior tag (first
# public release), notes list the full repo history the same way. Edit the release on GitHub
# afterward if you want prose or grouping.
#
# Commit all app/source changes before running: the tag must point at a tree that includes the full
# app, not only version-string files.
#
# Prerequisites: create-dmg (brew install create-dmg), gh (brew install gh)

set -e  # exit on any error

# ── Args ──────────────────────────────────────────────────────────────────────

BUMP_ONLY=false
VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bump-only) BUMP_ONLY=true; shift ;;
    *)
      if [ -n "$VERSION" ]; then
        echo "Usage: ./release.sh <version> [--bump-only]"
        exit 1
      fi
      VERSION="$1"
      shift
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version> [--bump-only]  (e.g. ./release.sh 2.4.1 --bump-only)"
  exit 1
fi

if git rev-parse "refs/tags/v$VERSION" >/dev/null 2>&1; then
  echo "✗ Git tag v$VERSION already exists locally. Remove it or choose another version."
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "✗ Working tree is not clean. Commit or stash all changes first so the v$VERSION tag includes the full app."
  git status -sb
  exit 1
fi

FILE_MARKETING=$(grep "MARKETING_VERSION" Binky.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //;s/;//')
FILE_BUILD=$(grep "CURRENT_PROJECT_VERSION" Binky.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //;s/;//')
OLD_MARKETING="$FILE_MARKETING"

echo "▶ Releasing Binky v$VERSION (project marketing version is $FILE_MARKETING)"
echo ""

# ── 1. Bump version (skip if project + site already at $VERSION) ─────────────

if [ "$FILE_MARKETING" != "$VERSION" ]; then
  echo "→ Bumping version in project.pbxproj…"
  sed -i '' "s/MARKETING_VERSION = $FILE_MARKETING/MARKETING_VERSION = $VERSION/g" \
    Binky.xcodeproj/project.pbxproj
  sed -i '' "s/CURRENT_PROJECT_VERSION = $FILE_BUILD/CURRENT_PROJECT_VERSION = $VERSION/g" \
    Binky.xcodeproj/project.pbxproj
else
  echo "→ Project already at $VERSION (skipping pbxproj bump)"
fi

# ── 2. Update site ────────────────────────────────────────────────────────────

if [ "$OLD_MARKETING" != "$VERSION" ]; then
  echo "→ Updating site/index.html…"
  sed -E -i '' "s|\"softwareVersion\": \"[0-9]+\.[0-9]+\.[0-9]+\"|\"softwareVersion\": \"$VERSION\"|g" site/index.html
  sed -E -i '' "s|v[0-9]+\.[0-9]+\.[0-9]+/Binky-[0-9]+\.[0-9]+\.[0-9]+\.dmg|v$VERSION/Binky-$VERSION.dmg|g" site/index.html
  sed -E -i '' "s|v[0-9]+\.[0-9]+\.[0-9]+ · Requires|v$VERSION · Requires|g" site/index.html

  echo "→ Updating site/llms.txt…"
  sed -E -i '' "s|Download v[0-9]+\.[0-9]+\.[0-9]+:|Download v$VERSION:|g" site/llms.txt
  sed -E -i '' "s|v[0-9]+\.[0-9]+\.[0-9]+/Binky-[0-9]+\.[0-9]+\.[0-9]+\.dmg|v$VERSION/Binky-$VERSION.dmg|g" site/llms.txt

  if [ -f site/homepage.md ]; then
    echo "→ Updating site/homepage.md…"
    sed -E -i '' "s|v[0-9]+\.[0-9]+\.[0-9]+/Binky-[0-9]+\.[0-9]+\.[0-9]+\.dmg|v$VERSION/Binky-$VERSION.dmg|g" site/homepage.md
  fi

  if compgen -G "site/compare/*/index.html" > /dev/null || [ -f site/compare/index.html ]; then
    echo "→ Updating site/compare/**/index.html…"
    for f in site/compare/*/index.html site/compare/index.html; do
      [ -f "$f" ] || continue
      sed -E -i '' "s|v[0-9]+\.[0-9]+\.[0-9]+ · Requires|v$VERSION · Requires|g" "$f"
      sed -E -i '' "s|v[0-9]+\.[0-9]+\.[0-9]+/Binky-[0-9]+\.[0-9]+\.[0-9]+\.dmg|v$VERSION/Binky-$VERSION.dmg|g" "$f"
    done
  fi
else
  echo "→ Site strings already match v$VERSION (skipping site sed)"
fi

if [ "$BUMP_ONLY" = true ]; then
  echo ""
  echo "✓ Bump only — updated project + site strings to v$VERSION."
  echo "  Commit those files, then: ./release.sh $VERSION  (full build, tag, gh release)"
  exit 0
fi

PREV_GIT_TAG=$(git tag -l 'v*' --sort=-version:refname | head -1 || true)
if [ -z "$PREV_GIT_TAG" ]; then
  echo "→ No previous v* tags (treating this as first public release for release notes)."
fi

# ── 3. Build ──────────────────────────────────────────────────────────────────

echo "→ Building Release…"
xcodebuild -scheme Binky -configuration Release -derivedDataPath build clean build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

# ── 4. Create DMG ─────────────────────────────────────────────────────────────

echo "→ Creating Binky-$VERSION.dmg…"
rm -f "Binky-$VERSION.dmg"
create-dmg \
  --volname "Binky" \
  --volicon "build/Build/Products/Release/Binky.app/Contents/Resources/AppIcon.icns" \
  --background "dmg-background.tiff" \
  --window-pos 200 120 \
  --window-size 420 520 \
  --icon-size 100 \
  --icon "Binky.app" 210 160 \
  --hide-extension "Binky.app" \
  --app-drop-link 210 370 \
  "Binky-$VERSION.dmg" \
  "build/Build/Products/Release/Binky.app"

echo "→ Creating Binky-$VERSION.zip (for in-app updater)…"
rm -f "Binky-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent \
  "build/Build/Products/Release/Binky.app" \
  "Binky-$VERSION.zip"

CASK_SHASUM=$(shasum -a 256 "Binky-$VERSION.zip" | awk '{print $1}')
echo "→ Updating Casks/binky.rb (version $VERSION, sha256)…"
sed -i '' "s/version \".*\"/version \"$VERSION\"/" Casks/binky.rb
sed -i '' "s/sha256 \".*\"/sha256 \"$CASK_SHASUM\"/" Casks/binky.rb

# ── 5. Optional bump commit, push, tag, release ─────────────────────────────

echo "→ Committing version files (if changed by this run)…"
git add Casks/binky.rb Binky.xcodeproj/project.pbxproj site/index.html site/llms.txt README.md
[ -f site/homepage.md ] && git add site/homepage.md
if compgen -G "site/compare/*/index.html" > /dev/null; then
  git add site/compare/*/index.html
fi
[ -f site/compare/index.html ] && git add site/compare/index.html
if git diff --cached --quiet; then
  echo "  (nothing to commit — version already in repo)"
else
  git commit -m "Bump to v$VERSION"
fi
git push origin main

echo "→ Tagging and publishing release…"
git tag "v$VERSION"
git push origin "v$VERSION"

if [ -n "$PREV_GIT_TAG" ]; then
  echo "→ Composing release notes from git ($PREV_GIT_TAG..HEAD, excluding version bump)…"
else
  echo "→ Composing release notes from git (full history, excluding version bump)…"
fi
NOTES_FILE=$(mktemp)
{
  echo "## Binky $VERSION"
  echo ""
  if [ -n "$PREV_GIT_TAG" ]; then
    echo "Changes since **$PREV_GIT_TAG** (commit subjects from this repo):"
  else
    echo "First public release — commit subjects from this repo (chronological):"
  fi
  echo ""
  if [ -n "$PREV_GIT_TAG" ] && git rev-parse "$PREV_GIT_TAG" >/dev/null 2>&1; then
    LIST=$(git log --no-merges "$PREV_GIT_TAG"..HEAD --pretty=format:'%s' --reverse | grep -vFx "Bump to v$VERSION" || true)
    if [ -n "$LIST" ]; then
      echo "$LIST" | while IFS= read -r subject; do
        [ -n "$subject" ] && echo "- $subject"
      done
    else
      echo "- *(No commits listed besides the version bump — describe this release manually on GitHub if needed.)*"
    fi
  elif [ -n "$PREV_GIT_TAG" ]; then
    echo "- **Warning:** git tag \`$PREV_GIT_TAG\` not found locally. Run \`git fetch --tags\` or edit release notes on GitHub."
  else
    LIST=$(git log --no-merges --pretty=format:'%s' --reverse | grep -vFx "Bump to v$VERSION" || true)
    if [ -n "$LIST" ]; then
      echo "$LIST" | while IFS= read -r subject; do
        [ -n "$subject" ] && echo "- $subject"
      done
    else
      echo "- *(No commit subjects found — describe this release manually on GitHub if needed.)*"
    fi
  fi
  echo ""
  echo "## Install"
  echo ""
  echo "**Homebrew (optional):**"
  echo ""
  echo "\`\`\`bash"
  echo "brew tap heyderekj/binky https://github.com/heyderekj/binky"
  echo "brew install --cask binky"
  echo "\`\`\`"
  echo ""
  echo "**Or** download **Binky-$VERSION.dmg** from the assets below and drag **Binky** into Applications. Already using Binky? Choose **Install Update** from the in-app banner when it appears."
  echo ""
  echo "## Finder “Open With” shows two Binkys"
  echo ""
  echo "macOS lists each **Binky.app** on disk with its own version. After an upgrade, an older copy is often still around."
  echo ""
  echo "- **Homebrew:** \`brew cleanup binky\` (or \`brew cleanup\`) removes old cask versions under Caskroom."
  echo '- **List every copy:** `mdfind '\''kMDItemCFBundleIdentifier == "com.binky.app"'\''` in Terminal; delete extras you do not need (e.g. in Downloads).'
} > "$NOTES_FILE"

gh release create "v$VERSION" \
  "Binky-$VERSION.dmg" \
  "Binky-$VERSION.zip" \
  --title "Binky $VERSION" \
  --notes-file "$NOTES_FILE" \
  --verify-tag

rm -f "$NOTES_FILE"

echo ""
echo "✓ Binky v$VERSION released."
echo "  https://github.com/heyderekj/binky/releases/tag/v$VERSION"
