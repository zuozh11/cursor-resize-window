# cursor-resize-window

`cursor-resize-window` is a small macOS utility that recreates yabai-style window resizing without running yabai itself. Hold `ctrl`, left-click anywhere in a window, and drag to resize from the nearest quadrant.

## Build and Run

```sh
swift build
swift test
swift run cursor-resize-window
```

The app uses macOS Accessibility APIs and a global event tap. On first run, approve it in System Settings > Privacy & Security > Accessibility. If the event tap cannot be created, also check Input Monitoring permissions.

## Homebrew

A formula template lives at `Formula/cursor-resize-window.rb`. After the first tagged release, update the `url` and `sha256`, then install locally with:

```sh
brew install --build-from-source Formula/cursor-resize-window.rb
brew services start cursor-resize-window
```
