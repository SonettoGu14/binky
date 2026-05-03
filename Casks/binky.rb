cask "binky" do
  version "1.4.0"
  # Refresh this checksum when publishing `Binky-{version}.zip` via `./release.sh`
  # (a local ad-hoc build can produce a different hash than the signed release artifact).
  sha256 "48bef7814d303629719b80edde93bb94479894609f3f60b5c8b2ff60020f8130"

  url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip",
      verified: "github.com/heyderekj/binky/"
  name "Binky"
  desc "Downloads inbox organizer — sort, route, tag, and review files"
  homepage "https://binkyfiles.com/"

  depends_on macos: ">= :sonoma"

  app "Binky.app"
end
