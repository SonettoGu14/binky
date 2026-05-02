cask "binky" do
  version "1.1.0"
  # Refresh this checksum when publishing `Binky-{version}.zip` via `./release.sh`
  # (a local ad-hoc build can produce a different hash than the signed release artifact).
  sha256 "fc1b46d324f10a8fd41604d654c5d87b99fc070982d47c7b8d3de1846ca59fcc"

  url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip"
  name "Binky"
  desc "Downloads inbox organizer — sort, route, tag, and review files"
  homepage "https://binkyfiles.com"

  depends_on macos: ">= :sonoma"

  app "Binky.app"
end
