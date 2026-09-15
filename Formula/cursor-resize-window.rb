class CursorResizeWindow < Formula
  desc "Resize macOS windows with ctrl-left-drag"
  homepage "https://github.com/zuozh11/cursor-resize-window"
  url "https://github.com/zuozh11/cursor-resize-window/archive/refs/tags/v0.1.22.tar.gz"
  sha256 "b3ec6d3df007efb35b58fdf3cdaba282b2d9dd2e479bbdacc63de1a3e6a63923"
  license "MIT"

  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "--configuration", "release", "--disable-sandbox"
    bin.install ".build/release/cursor-resize-window"
    libexec.install "scripts/run-service.sh"
    chmod 0755, libexec/"run-service.sh"
  end

  service do
    run [libexec/"run-service.sh"]
    keep_alive true
    log_path var/"log/cursor-resize-window.log"
    error_log_path var/"log/cursor-resize-window.log"
  end

  test do
    assert_predicate bin/"cursor-resize-window", :executable?
    assert_predicate libexec/"run-service.sh", :executable?
  end
end
