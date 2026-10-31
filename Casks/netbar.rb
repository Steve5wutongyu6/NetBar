cask "netbar" do
  version "1.0.3"
  sha256 "bad1e52cffc7d998386dbc1da474f2120f559163426a993e2d3776f1f2cbc241"

  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v#{version}/NetBar-v#{version}.zip"
  name "NetBar"
  desc "Menu bar Wi-Fi list with Personal Hotspot signal and battery"
  homepage "https://github.com/Steve5wutongyu6/NetBar"

  depends_on macos: :tahoe

  app "NetBar.app"
end
