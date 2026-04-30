cask "binky" do
  version "2.7.12"
  # Refresh this checksum when publishing `Binky-{version}.zip` via `./release.sh`.
  sha256 "e01ea47d75b736bd928cfc0e9d081fb46cf2d2c6940a6226a051a49fe01a9b15"

  url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip"
  name "Binky"
  desc "Downloads inbox organizer — sort, route, tag, and review files"
  homepage "https://binkyfiles.com"

  depends_on macos: ">= :sequoia"

  app "Binky.app"
end
