cask "netbar" do
  version "1.0.1"
  sha256 "83b2b4f8e30cbf013da45a259eaf177a98891a71e3e76531b826cabe32de415d"

  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v#{version}/NetBar-v#{version}.zip"
  name "NetBar"
  desc "Menu bar Wi-Fi list with Personal Hotspot signal and battery"
  homepage "https://github.com/Steve5wutongyu6/NetBar"

  depends_on macos: :tahoe

  app "NetBar.app"
end
