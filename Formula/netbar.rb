class Netbar < Formula
  desc "Menu bar Wi-Fi list with Personal Hotspot signal and battery"
  homepage "https://github.com/Steve5wutongyu6/NetBar"
  url "https://github.com/Steve5wutongyu6/NetBar/releases/download/v1.0.1/netbar-v1.0.1-src.tar.gz"
  sha256 "260d00347d546834ca054791a62f99a15e3d7fde1a32bd4a90aacfacd614f533"
  license "MIT"
  head "https://github.com/Steve5wutongyu6/NetBar.git", branch: "main"

  depends_on "rust" => :build
  depends_on :macos

  def install
    # The project builds against the newest SDK; a machine with an older one
    # still builds, against what it has.
    ENV["NETBAR_ALLOW_OLDER_SDK"] = "1"
    # Homebrew provides its own cargo without rustup; build the host slice.
    ENV["NETBAR_PLAIN_CARGO"] = "1"
    system "./Scripts/build-rust.sh"
    system "./Scripts/build.sh", "--release"

    app = Pathname("build/Release/NetBar.app")
    odie "NetBar.app was not produced" unless app.exist?

    prefix.install app
    (bin/"netbar").write <<~SH
      #!/bin/bash
      exec /usr/bin/open "#{opt_prefix}/NetBar.app" --args "$@"
    SH
    chmod 0755, bin/"netbar"
  end

  def caveats
    <<~EOS
      NetBar runs from the menu bar. Start it with:
        netbar
      To start it at login, add NetBar.app in System Settings > General > Login Items.
    EOS
  end

  test do
    assert_path_exists prefix/"NetBar.app"
    assert_path_exists bin/"netbar"
  end
end
