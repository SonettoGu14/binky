cask "binky" do
  version "1.5.0"
  # Refresh this checksum when publishing `Binky-{version}.zip` via `./release.sh`
  # (a local ad-hoc build can produce a different hash than the signed release artifact).
  sha256 "ae4beed5d71741a5a4230fadadecf7df920305a687a28f2e3980c9194808a919"

  url "https://github.com/heyderekj/binky/releases/download/v#{version}/Binky-#{version}.zip",
      verified: "github.com/heyderekj/binky/"
  name "Binky"
  desc "Downloads inbox organizer — sort, route, tag, and review files"
  homepage "https://binkyfiles.com/"

  depends_on macos: ">= :sonoma"

  app "Binky.app"
end
