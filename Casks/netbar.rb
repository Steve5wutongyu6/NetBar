cask "netbar" do
  version "1.0.0"
  sha256 "50f67d408775f7df2d9c9d0d7ce4b0afbc00ad7668e8fdfef5c679e329da554c"

  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v#{version}/NetBar-v#{version}.zip",
      verified: "github.com/Steve5wutongyu6/NetBar/"
  name "NetBar"
  desc "Menu bar Wi-Fi list with Personal Hotspot signal and battery"
  homepage "https://github.com/Steve5wutongyu6/NetBar"

  depends_on macos: :tahoe

  app "NetBar.app"
end
