cask "netbar" do
  version "1.0.7"
  sha256 "d7a5dc3c439d01d6a1071dfb7b955edbd4ff8dad86d0f0cefa4f099e36440bc8"

  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v#{version}/NetBar-v#{version}.zip"
  name "NetBar"
  desc "Menu bar Wi-Fi list with Personal Hotspot signal and battery"
  homepage "https://github.com/Steve5wutongyu6/NetBar"

  depends_on macos: :tahoe

  app "NetBar.app"
end
