class CursorResizeWindow < Formula
  desc "Resize macOS windows with ctrl-left-drag"
  homepage "https://github.com/zuozh11/cursor-resize-window"
  url "https://github.com/zuozh11/cursor-resize-window/archive/refs/tags/v0.1.2.tar.gz"
  sha256 "27b5d738c0fa3126add09826edaae393ea5f75534a1a828059c219e7c0eab062"
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
