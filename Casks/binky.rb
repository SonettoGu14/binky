cask "binky" do
  version "1.3.1"
  # Refresh this checksum when publishing `Binky-{version}.zip` via `./release.sh`
  # (a local ad-hoc build can produce a different hash than the signed release artifact).
  sha256 "f239a5278fedf93dbdf7ede8f8a7a722e0f9f1a8a5c22244576dba71a611a24b"

  url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip",
      verified: "github.com/heyderekj/binky/"
  name "Binky"
  desc "Downloads inbox organizer — sort, route, tag, and review files"
  homepage "https://binkyfiles.com/"

  depends_on macos: ">= :sonoma"

  app "Binky.app"
end
