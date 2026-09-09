class CursorResizeWindow < Formula
  desc "Resize macOS windows with ctrl-left-drag"
  homepage "https://github.com/zuozh11/cursor-resize-window"
  url "https://github.com/zuozh11/cursor-resize-window/archive/refs/tags/v0.1.21.tar.gz"
  sha256 "a45b56e5b9fd544c43175d687ff63e8eba85bcc7eb95b76e81bcaba50ef07eff"
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
