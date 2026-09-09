class CursorResizeWindow < Formula
  desc "Resize macOS windows with ctrl-left-drag"
  homepage "https://github.com/zuozh11/cursor-resize-window"
  url "https://github.com/zuozh11/cursor-resize-window/archive/refs/tags/v0.1.20.tar.gz"
  sha256 "a132f3dace897ad63cb77e2a191fac8f13699a0fa0d7c4d54ef6b1a3247b69a8"
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
