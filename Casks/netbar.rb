cask "netbar" do
  version "1.0.2"
  sha256 "410e93a6d401b37cc3177ac8e22db66b99c2fda8d2e3db084f6b6698538f3728"

  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v#{version}/NetBar-v#{version}.zip"
  name "NetBar"
  desc "Menu bar Wi-Fi list with Personal Hotspot signal and battery"
  homepage "https://github.com/Steve5wutongyu6/NetBar"

  depends_on macos: :tahoe

  app "NetBar.app"
end
