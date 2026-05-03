cask "binky" do
  version "1.3.2"
  # Refresh this checksum when publishing `Binky-{version}.zip` via `./release.sh`
  # (a local ad-hoc build can produce a different hash than the signed release artifact).
  sha256 "150005a8bc73c268a38161a17a040ee9ba8aff6f9f1a9497715427abe4b0f61b"

  url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip",
      verified: "github.com/heyderekj/binky/"
  name "Binky"
  desc "Downloads inbox organizer — sort, route, tag, and review files"
  homepage "https://binkyfiles.com/"

  depends_on macos: ">= :sonoma"

  app "Binky.app"
end
