# SnapClip — macOS Screenshot App

## Overview

SnapClip is a lightweight, stylish macOS screenshot tool built with Swift and SwiftUI. It provides region, window, full-screen, and scrolling capture with a full annotation toolkit and a modern minimal UI.

## Motivation

Existing screenshot tools like Xnip are feature-rich but visually dated and cluttered. SnapClip aims to deliver the same core functionality with a cleaner, more modern design — fewer buttons, better typography, smoother animations.

## Requirements

1. **Global Hotkey:** Default `Cmd+Shift+X` triggers the capture overlay. Hotkey is user-configurable in Preferences.
2. **Capture Modes:**
   - **Region:** Drag to select a rectangular area. Show live dimensions (px) while dragging.
   - **Window:** Click any window to capture it (with optional shadow).
   - **Full Screen:** Capture the entire screen (or selected display for multi-monitor setups).
   - **Scrolling Capture:** Capture long/scrollable content by auto-scrolling and stitching frames.
3. **Annotation Tools** (available in the post-capture editor):
   - Rectangle, ellipse, line, arrow
   - Freehand pen / marker (with adjustable thickness and color)
   - Text insertion (font size, color)
   - Highlight (semi-transparent overlay)
   - Blur / mosaic (for redacting sensitive info)
   - Numbered steps (auto-incrementing circled numbers)
   - Crop and resize
4. **Post-Capture Flow:**
   - After capture, show a floating preview window with the screenshot.
   - Toolbar: Copy to Clipboard, Save to File, Annotate, Close.
   - Save dialog defaults to `~/Desktop` with filename `SnapClip_YYYY-MM-DD_HH-mm-ss.png`.
   - Configurable default save directory in Preferences.
5. **Menu Bar App:**
   - Runs as a menu bar icon (no Dock icon by default).
   - Menu bar dropdown: New Screenshot, Preferences, Quit.
6. **Preferences:**
   - Global hotkey configuration
   - Default save directory
   - Image format (PNG / JPEG with quality slider)
   - Include window shadow (on/off)
   - Launch at login toggle
7. **UI/UX:**
   - Dark/light mode following system appearance, with optional override.
   - Smooth animations for overlay appear/dismiss.
   - Frosted-glass / vibrancy effects in toolbars.
   - Minimal chrome — tools appear contextually, not all at once.

## Acceptance Criteria

- [ ] `Cmd+Shift+X` activates region capture overlay from any app.
- [ ] User can switch between region, window, and full-screen modes via modifier keys or toolbar.
- [ ] Scrolling capture works on Safari, Chrome, and native scroll views.
- [ ] All 8 annotation tools function correctly in the editor.
- [ ] Copy to clipboard produces a valid PNG image.
- [ ] Save to file writes to the configured directory with correct naming.
- [ ] Preferences persist between app launches.
- [ ] App runs as menu bar agent (no Dock icon).
- [ ] App requests and handles Screen Recording permission gracefully.

## Technical Approach

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI with AppKit interop for overlay windows and global hotkey registration.
- **Screen Capture:** `ScreenCaptureKit` (macOS 13+) for region/window/screen capture.
- **Global Hotkey:** `CGEvent` tap or a library like `HotKey` for global shortcut registration.
- **Scrolling Capture:** Accessibility API (`AXUIElement`) to detect scroll views + programmatic scrolling + frame stitching with Core Image.
- **Annotation Rendering:** SwiftUI Canvas with custom gesture recognizers.
- **Persistence:** `UserDefaults` for preferences; images saved via `NSBitmapImageRep`.
- **Distribution:** Native `.app` bundle, minimum deployment target macOS 13 (Ventura).

## Out of Scope

- Cloud upload / sharing links
- Screen recording / video capture
- OCR / text recognition
- Plugin system
- iOS / iPadOS version

## Open Questions

- Should we support Retina (2x) and non-Retina displays with different DPI handling? (Assumed yes, auto-detect.)
- Pin-to-desktop (Xnip-style floating screenshot)? (Deferred to v2.)
