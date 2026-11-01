cask "netbar" do
  version "1.0.5"
  sha256 "af1580e6df2b8d4cf846e8f77ca5a52c5990bde32683247f6e7da4f1625d458f"

  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v#{version}/NetBar-v#{version}.zip"
  name "NetBar"
  desc "Menu bar Wi-Fi list with Personal Hotspot signal and battery"
  homepage "https://github.com/Steve5wutongyu6/NetBar"

  depends_on macos: :tahoe

  app "NetBar.app"
end
