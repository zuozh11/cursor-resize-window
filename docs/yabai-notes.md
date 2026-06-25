# yabai Mouse Resize Notes

The target behavior is the yabai-style mouse workflow:

- Hold a configured modifier key.
- Press the left mouse button on a window.
- Drag to resize the window from the quadrant where the drag started.

This project implements that as a standalone macOS utility with:

- `CGEvent.tapCreate` for global mouse down, drag, and up events.
- `AXUIElementCopyElementAtPosition` to find the Accessibility element under the pointer.
- `kAXPositionAttribute` and `kAXSizeAttribute` updates to resize the enclosing window.

The initial behavior deliberately locks the resize quadrant at mouse-down time. That avoids direction switching during a drag and keeps the interaction predictable.
