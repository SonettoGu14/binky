# Homebrew cask (custom tap in this repo)

**Decision:** Binky is distributed via a **cask in this application repository**, not a separate `homebrew-*` tap repo. Users add it once with a custom remote:

```bash
brew tap heyderekj/binky https://github.com/heyderekj/binky
brew install --cask binky
```

**Rationale:** One repo, one source of truth; [release.sh](../release.sh) updates `binky.rb` (version and `sha256` from the release zip) on every publish. No sync step with a second Homebrew repository.

**After upgrades:** Homebrew keeps previous cask payloads under `Caskroom` until cleanup. That can make Finder’s **Open With** menu show two Binkys (two versions). Run `brew cleanup binky` or `brew cleanup` to drop old installs.

**Optional later:** A maintainer or community member can also open a pull request to [homebrew-cask](https://github.com/Homebrew/homebrew-cask) so `brew install --cask binky` works without a tap, subject to Homebrew’s notability and audit rules. This file does not block that; the cask format is the same.
