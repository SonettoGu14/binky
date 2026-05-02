cask "binky" do
  version "1.1.2"
  # Refresh this checksum when publishing `Binky-{version}.zip` via `./release.sh`
  # (a local ad-hoc build can produce a different hash than the signed release artifact).
  sha256 "dc5fce60d186d3da9e5512743b1a59130cdbd4d67bc89dbf0bb8174ceb1f7607"

  url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip",
      verified: "github.com/heyderekj/binky/"
  name "Binky"
  desc "Downloads inbox organizer — sort, route, tag, and review files"
  homepage "https://binkyfiles.com/"

  depends_on macos: ">= :sonoma"

  app "Binky.app"
end
