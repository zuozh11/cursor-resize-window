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

Center dragging moves the window through the Accessibility API (AX). The pointer stays at its physical position, and the region preview follows the requested window frame. Center dragging does not use title-bar event redirection, pointer warping, or native macOS edge tiling.

The middle quarter of each axis forms a cross-shaped region: the left and right arms resize width, while the top and bottom arms resize height. The four outer corner regions resize both axes. Dragging from the center intersection moves the window freely in any direction.

Edge and corner resizing redirects the drag to the corresponding native resize position when it is clickable on the pointer's display. Otherwise, it uses Accessibility resizing. Native resize positions stay 20 points inside the visible area's top, left, and right edges and 8 points inside its bottom edge.

During native resizing, a shadow cursor stays under the user's pointer while a red dot marks the rewritten resize position. This uses private macOS Window Server symbols; when unavailable, resizing keeps its original event translation. Accessibility resizing does not display the region preview.

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
