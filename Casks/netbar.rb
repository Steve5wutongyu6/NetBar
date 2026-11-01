cask "netbar" do
  version "1.0.8"
  sha256 "73bc248e5eb7dfa9fc72241ab241c5c5595e9dd70b91492a8c7f34613e0343c2"

  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v#{version}/NetBar-v#{version}.zip"
  name "NetBar"
  desc "Menu bar Wi-Fi list with Personal Hotspot signal and battery"
  homepage "https://github.com/Steve5wutongyu6/NetBar"

  depends_on macos: :tahoe

  app "NetBar.app"
end
