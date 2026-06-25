# cursor-resize-window

`cursor-resize-window` is a small macOS utility that recreates yabai-style window resizing without running yabai itself. Hold `ctrl`, left-click anywhere in a window, and drag to resize from the nearest quadrant.

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
