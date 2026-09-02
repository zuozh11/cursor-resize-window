# cursor-resize-window

`cursor-resize-window` is a small macOS utility that recreates yabai-style window resizing without running yabai itself. Hold `ctrl`, left-click anywhere in a window, and drag to resize from the selected edge or corner.

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

Then hold `ctrl`, left-click a window, and drag to resize it.

The middle third of each axis forms a cross-shaped edge region: the left and right arms resize width, while the top and bottom arms resize height. The four outer corner regions resize both axes. In the center intersection, the nearest center line selects the axis, with width winning ties.

The utility redirects the drag to the selected macOS resize edge or corner so Window Server performs the resize whenever that target is on the same active display as the pointer. If the target is off-screen or on another display, it falls back to updating the window frame through the Accessibility API.

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
