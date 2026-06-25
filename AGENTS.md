# Repository Guidelines

## Project Structure & Module Organization

This repository is a Swift Package Manager macOS utility. Core logic lives in `Sources/CursorResizeWindowCore`, including Accessibility API access, resize geometry, and global mouse event handling. The command-line entry point is intentionally thin and lives in `Sources/CursorResizeWindowCLI/main.swift`. Unit tests belong in `Tests/CursorResizeWindowCoreTests`. Homebrew packaging work goes under `Formula/`.

## Build, Test, and Development Commands

- `swift build`: compile the package in debug mode.
- `swift test`: run the XCTest suite.
- `swift run cursor-resize-window`: run the tool locally with `ctrl` as the only trigger key.
- `swift build -c release`: produce the release binary used by the Homebrew formula.

The tool requires macOS Accessibility permission, and global event taps may also require Input Monitoring permission.

## Coding Style & Naming Conventions

Use Swift 6 style with 4-space indentation. Keep runtime behavior in `CursorResizeWindowCore`, while `CursorResizeWindowCLI` should only start the application. Prefer explicit names such as `WindowResizeApp` and `ResizeModel`. Avoid new dependencies unless they remove meaningful complexity.

## Testing Guidelines

Use XCTest for deterministic logic such as resize geometry. Name tests after expected behavior, for example `testResizesRightBottomUsingIncrementalDelta`. Runtime Accessibility and event-tap behavior should be verified manually on macOS until an integration harness exists.

## Commit & Pull Request Guidelines

Use concise, imperative commit subjects such as `Initialize Swift package` or `Align resize drag behavior`. Keep unrelated changes out of the same commit. Pull requests should describe the user-visible behavior, list manual macOS permission checks performed, link related issues, and include screenshots or screen recordings when resizing behavior changes.

## Security & Configuration Tips

Do not commit logs, signing identities, or Homebrew release checksums before the matching release artifact exists. Keep behavior narrow and predictable: `ctrl` is the only trigger key, and resize behavior should stay aligned with yabai unless intentionally changed.
