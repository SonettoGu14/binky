cask "binky" do
  version "1.0.4"
  # Refresh this checksum when publishing `Binky-{version}.zip` via `./release.sh`
  # (a local ad-hoc build can produce a different hash than the signed release artifact).
  sha256 "a69cf5631e3c2eb97ce9a1d76bb360347db0fb3a40db1b1e38dc58fc6bec5381"

  url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip"
  name "Binky"
  desc "Downloads inbox organizer — sort, route, tag, and review files"
  homepage "https://binkyfiles.com"

  depends_on macos: ">= :sonoma"

  app "Binky.app"
end
