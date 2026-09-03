# cursor-resize-window

`cursor-resize-window` is a small macOS utility that recreates yabai-style window dragging without running yabai itself. Hold `ctrl`, left-click anywhere in a window, and drag to resize from the selected edge or corner or to move it from the center.

## Install

```sh
brew tap zuozh11/tap
brew install cursor-resize-window
```

The app uses macOS Accessibility APIs and a global event tap. On first run, approve your terminal or Homebrew service host in System Settings > Privacy & Security > Accessibility. If the event tap cannot be created, also check Input Monitoring permissions.

## Usage

Run in the foreground:

```sh
cursor-resize-window
```

Then hold `ctrl`, left-click a window, and drag to resize or move it.

A red dot tracks the rewritten mouse position that macOS receives during native window movement and resizing. It disappears when the gesture ends and is not shown for Accessibility-based fallback resizing.

The middle third of each axis forms a cross-shaped region: the left and right arms resize width, while the top and bottom arms resize height. The four outer corner regions resize both axes. Dragging from the center intersection moves the window freely in any direction.

The utility redirects the drag to the selected macOS resize edge, corner, or title bar so Window Server performs the operation whenever that target is on the same active display as the pointer. If a resize target is off-screen or on another display, it falls back to updating the window frame through the Accessibility API. Moving is native-only, so a center drag is left untouched when its title-bar target is not clickable on the pointer's display.

## Service Commands

Start now and automatically run at login:

```sh
brew services start zuozh11/tap/cursor-resize-window
```

Stop and disable automatic login startup:

```sh
brew services stop zuozh11/tap/cursor-resize-window
```

Restart after upgrading:

```sh
brew services restart zuozh11/tap/cursor-resize-window
```

Check service state:

```sh
brew services list
```

## Development

```sh
swift build
swift test
swift run cursor-resize-window
```
