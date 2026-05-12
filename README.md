# SnapClip

Lightweight macOS screenshot app — menu bar agent, global hotkey, region/window/full-screen capture via ScreenCaptureKit.

## Requirements
- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 5.9+

## Build & Run

```bash
./scripts/build-app.sh
open .build/SnapClip.app
```

The first run will prompt for **Screen Recording** permission (System Settings → Privacy & Security → Screen Recording) and **Accessibility** for the global hotkey event tap (System Settings → Privacy & Security → Accessibility).

## Usage
- Click the camera icon in the menu bar, or press `⌘⇧X` from any app.
- In the overlay: `Tab` cycles modes (Region → Window → Full Screen), `Esc` cancels.
- Drag to select a region, click a window, or click anywhere in full-screen mode.
- Preview window opens with **Copy**, **Save**, **Annotate** (placeholder), and **Close**.

## Project Layout

```
Sources/SnapClip/
├── SnapClipApp.swift          # @main App entry
├── AppDelegate.swift          # Menu bar, hotkey wiring, lifecycle
├── HotKeyManager.swift        # Global ⌘⇧X via CGEvent tap
├── CaptureController.swift    # Orchestrates overlay → capture → preview
├── ScreenCaptureService.swift # ScreenCaptureKit wrapper
├── PermissionService.swift    # Screen Recording permission
├── OverlayWindow.swift        # Borderless full-screen overlay window
├── OverlayRootView.swift      # SwiftUI overlay UI (region/window/full)
├── PreviewWindow.swift        # Floating post-capture preview window
├── PreviewView.swift          # SwiftUI preview content
├── PreferencesView.swift      # Settings scene placeholder
└── SnapClip-Info.plist        # Bundle Info.plist (LSUIElement)
```
