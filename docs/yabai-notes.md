# yabai Mouse Resize Notes

The target behavior is the yabai-style mouse workflow:

- Hold `ctrl`.
- Press the left mouse button on a window.
- Drag to resize the window from the quadrant where the drag started.

This project implements that as a standalone macOS utility with:

- `CGEvent.tapCreate` for global mouse down, drag, and up events.
- `AXUIElementCopyElementAtPosition` to find the Accessibility element under the pointer.
- `kAXPositionAttribute` and `kAXSizeAttribute` updates to resize the enclosing window.

The resize model mirrors yabai's floating-window path: lock the handle direction at mouse-down time, apply incremental deltas against the current frame, clamp width and height to at least `1`, and throttle resize updates to roughly `67.67ms`.
