cask "netbar" do
  version "1.0.1"
  sha256 "c75625b29ed7701f059340965304609060ac55f179adb39f23be634fee30018f"

  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v#{version}/NetBar-v#{version}.zip",
      verified: "github.com/Steve5wutongyu6/NetBar/"
  name "NetBar"
  desc "Menu bar Wi-Fi list with Personal Hotspot signal and battery"
  homepage "https://github.com/Steve5wutongyu6/NetBar"

  depends_on macos: :tahoe

  app "NetBar.app"
end
