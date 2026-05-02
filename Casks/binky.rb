cask "binky" do
  version "1.0.5"
  # Refresh this checksum when publishing `Binky-{version}.zip` via `./release.sh`
  # (a local ad-hoc build can produce a different hash than the signed release artifact).
  sha256 "2e288fe66212f0b5aaa58b7989ae63484c1087e7709d6f54ad2ae5a9610bdb11"

  url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip"
  name "Binky"
  desc "Downloads inbox organizer — sort, route, tag, and review files"
  homepage "https://binkyfiles.com"

  depends_on macos: ">= :sonoma"

  app "Binky.app"
end
