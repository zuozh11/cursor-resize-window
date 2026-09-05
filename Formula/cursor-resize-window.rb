class CursorResizeWindow < Formula
  desc "Resize macOS windows with ctrl-left-drag"
  homepage "https://github.com/zuozh11/cursor-resize-window"
  url "https://github.com/zuozh11/cursor-resize-window/archive/refs/tags/v0.1.13.tar.gz"
  sha256 "c48c736daba13475ac7a0aa619adb5c31d8bb7b2f3dac1d5af5e46afce6a45ef"
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
    assert_predicate bin/"cursor-resize-window", :executable?
  end
end
