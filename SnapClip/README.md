# SnapClip — Preferences, Persistence, Scrolling Capture & UI Polish

This module covers the configuration surface and long-form capture for SnapClip.

## Modules

- `Settings/SettingsManager.swift` — `ObservableObject` singleton backed by `UserDefaults`.
  Stores hotkey binding, save directory (security-scoped bookmark), image format,
  JPEG quality, window-shadow toggle, launch-at-login state, and appearance override.
- `Settings/LaunchAtLoginController.swift` — wraps `SMAppService.mainApp` (macOS 13+).
- `Preferences/PreferencesWindow.swift` — SwiftUI `TabView` with General, Capture and
  Appearance tabs. Includes a `HotkeyRecorderButton` that captures the next keystroke.
- `Save/ScreenshotSaver.swift` — `save(image:)` writes `SnapClip_YYYY-MM-DD_HH-mm-ss.{png,jpg}`
  to the configured directory; `saveAs(image:)` presents an `NSSavePanel` with the
  filename pre-filled.
- `ScrollingCapture/ScrollingCaptureService.swift` — async API: hit-tests the AX tree
  for an `AXScrollArea` / `AXWebArea`, drives the vertical scroll bar (native) or
  synthesises scroll-wheel events (browsers), captures frames with
  `CGWindowListCreateImage`, and stitches them with overlap detection in Core Image.

## Limitations

- **Browser scrolling is best-effort.** `AXWebArea` (Safari, Chrome, Edge) does not
  expose a writable scroll position via Accessibility, so we drive the page by
  synthesising `kCGEventScrollWheel` events at the element centre. This works for
  most pages but can misbehave on sticky headers, infinite-scroll lists, and
  JS-managed scroll containers. Native `NSScrollView` (`AXScrollArea`) uses the
  proper AX scroll-bar value setter and is reliable.
- **Sandbox + bookmarks.** The save directory is persisted as a security-scoped
  bookmark. Reads/writes go through `SettingsManager.withSaveDirectoryAccess { … }`
  which balances `startAccessingSecurityScopedResource()` and refreshes stale
  bookmarks on next access.
- `UI/VisualEffectBackground.swift` — `NSVisualEffectView` wrapper for frosted toolbars.
- `UI/Animations.swift` — shared spring animations and transitions for overlays/toolbars.

## Project layout

These sources are intended to drop into the existing SnapClip Xcode project under
`SnapClip/Sources/`. They have no third-party dependencies and target macOS 13+.
