cask "binky" do
  version "2.7.13"
  # Refresh this checksum when publishing `Binky-{version}.zip` via `./release.sh`
  # (a local ad-hoc build can produce a different hash than the signed release artifact).
  sha256 "3d361184727bd7c2a3d192e1a843bc66057956a3d7ab43fe4fe0d6b7b117886f"

  url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip"
  name "Binky"
  desc "Downloads inbox organizer — sort, route, tag, and review files"
  homepage "https://binkyfiles.com"

  depends_on macos: ">= :sonoma"

  app "Binky.app"
end
