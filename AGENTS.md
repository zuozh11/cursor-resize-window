# Repository Guidelines

## Project Structure & Module Organization

This repository is a Swift Package Manager macOS utility. Core logic lives in `Sources/CursorResizeWindowCore`, including configuration parsing, Accessibility API access, and global mouse event handling. The command-line entry point is intentionally thin and lives in `Sources/CursorResizeWindowCLI/main.swift`. Unit tests belong in `Tests/CursorResizeWindowCoreTests`. Homebrew packaging work goes under `Formula/`.

## Build, Test, and Development Commands

- `swift build`: compile the package in debug mode.
- `swift test`: run the XCTest suite.
- `swift run cursor-resize-window --modifier ctrl`: run the tool locally with the default modifier.
- `swift build -c release`: produce the release binary used by the Homebrew formula.

The tool requires macOS Accessibility permission, and global event taps may also require Input Monitoring permission.

## Coding Style & Naming Conventions

Use Swift 6 style with 4-space indentation. Keep CLI parsing and runtime window behavior separated: reusable logic goes in `CursorResizeWindowCore`, while `CursorResizeWindowCLI` should only translate process arguments into application startup. Prefer explicit names such as `WindowResizeApp`, `AppConfig`, and `MouseModifier`. Avoid new dependencies unless they remove meaningful complexity.

## Testing Guidelines

Use XCTest for deterministic logic such as config parsing, defaults, and argument validation. Name tests after expected behavior, for example `testCommandLineOverridesConfigFile`. Runtime Accessibility and event-tap behavior should be verified manually on macOS until an integration harness exists.

## Commit & Pull Request Guidelines

Use concise, imperative commit subjects such as `Initialize Swift package` or `Add modifier config parsing`. Keep unrelated changes out of the same commit. Pull requests should describe the user-visible behavior, list manual macOS permission checks performed, link related issues, and include screenshots or screen recordings when resizing behavior changes.

## Security & Configuration Tips

Do not commit personal config files, logs, signing identities, or Homebrew release checksums before the matching release artifact exists. Keep defaults conservative: `ctrl` is the default modifier, and minimum window size should prevent accidental zero-size windows.
