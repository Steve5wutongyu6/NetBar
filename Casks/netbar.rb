cask "netbar" do
  version "1.0.8"
  sha256 "94e8d78a6ecf3d62ab235ec0e194b9c3c95080781b38748fd22b1d2dd8d7d535"

  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v#{version}/NetBar-v#{version}.zip"
  name "NetBar"
  desc "Menu bar Wi-Fi list with Personal Hotspot signal and battery"
  homepage "https://github.com/Steve5wutongyu6/NetBar"

  depends_on macos: :tahoe

  app "NetBar.app"
end
