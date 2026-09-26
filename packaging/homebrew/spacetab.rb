# Homebrew cask for SpaceTab. Lives in the tap repository muhammad-Osman/homebrew-tap
# as Casks/spacetab.rb; scripts/release.sh fills in the version and checksum.
cask "spacetab" do
  version "0.9.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/muhammad-Osman/spacetab/releases/download/v#{version}/SpaceTab-#{version}.dmg"
  name "SpaceTab"
  desc "Ubuntu-style window switcher for the current desktop"
  homepage "https://github.com/muhammad-Osman/spacetab"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "SpaceTab.app"

  uninstall quit: "io.github.muhammad-osman.spacetab"

  zap trash: [
    "~/Library/Preferences/io.github.muhammad-osman.spacetab.plist",
  ]
end
