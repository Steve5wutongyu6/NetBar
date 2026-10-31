cask "netbar" do
  version "1.0.1"
  sha256 "b15f44c69e5d7964c0957a84620037cb9e95e76cc564a626bd0be7e3cb58a7b6"

  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v#{version}/NetBar-v#{version}.zip"
  name "NetBar"
  desc "Menu bar Wi-Fi list with Personal Hotspot signal and battery"
  homepage "https://github.com/Steve5wutongyu6/NetBar"

  depends_on macos: :tahoe

  app "NetBar.app"
end
