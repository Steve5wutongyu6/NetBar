cask "netbar" do
  version "1.0.4"
  sha256 "a897033ecd2e15c1ad8271e23d67de802fb5cd938d2e8ee01ec33353623e9384"

  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v#{version}/NetBar-v#{version}.zip"
  name "NetBar"
  desc "Menu bar Wi-Fi list with Personal Hotspot signal and battery"
  homepage "https://github.com/Steve5wutongyu6/NetBar"

  depends_on macos: :tahoe

  app "NetBar.app"
end
