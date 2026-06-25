class CursorResizeWindow < Formula
  desc "Resize macOS windows with a modifier key and left mouse drag"
  homepage "https://github.com/zuozhi/cursor-resize-window"
  url "https://github.com/zuozhi/cursor-resize-window/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "TODO"
  license "MIT"

  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "--configuration", "release", "--disable-sandbox"
    bin.install ".build/release/cursor-resize-window"
  end

  service do
    run [opt_bin/"cursor-resize-window"]
    keep_alive true
    log_path var/"log/cursor-resize-window.log"
    error_log_path var/"log/cursor-resize-window.log"
  end

  test do
    assert_match "cursor-resize-window", shell_output("#{bin}/cursor-resize-window --help")
  end
end
