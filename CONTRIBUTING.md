# Contributing to PDFReader

Thanks for helping out. This is a small native macOS app (SwiftUI + PDFKit,
built as a Swift Package with no Xcode project), so most contributions are
straightforward Swift changes plus headless verification.

Please note: this project is GPLv3. By contributing you agree your changes
are distributed under the same license (see `LICENSE`).

## Requirements

- macOS 14+, Intel or Apple Silicon.
- Swift 6 toolchain. Command Line Tools are enough for `swift build` and
  `swift run PDFReaderVerify`.
- Full Xcode is required only for `swift test` (XCTest).

## Quick start

```sh
git clone https://github.com/Marvelxy/PDFReader.git
cd PDFReader
swift build
swift run PDFReader

# Open a sample immediately:
PDFREADER_SAMPLE=~/Downloads/sample.pdf swift run PDFReader
```

For normal use (and correct cursors on macOS Tahoe), run as a bundle:

```sh
scripts/make-app.sh [debug|release]
open .build/app/PDFReader.app
```

## How to contribute

1. Fork the repo and create a topic branch from `main`:
   `git checkout -b feature/short-description`.
2. Make focused changes (one feature/fix per PR).
3. Verify locally (see below).
4. Push and open a pull request against `main` describing what changed,
   how you tested it, and any PDFs/screenshots that help review.

Keep PRs small and explain user-visible behavior changes. If you change
toolbar, sidebar, themes, or annotation behavior, include a screenshot or
short clip when practical.

## Verification (required before PR)

```sh
swift build                # must pass
swift run PDFReaderVerify  # headless checks, works with CLT
swift test                 # full XCTest suite, requires Xcode
```

CI (`.github/workflows/release.yml`) runs all three on every PR. Tagging
`v*` additionally builds the universal binary, app bundle, and DMG.

## Project layout

```
Sources/PDFReader/
  PDFReaderApp.swift
  Views/
    ContentView.swift   # split view, toolbar, status bar, themes
    PDFKitView.swift    # PDFView + PDFThumbnailView bridges
    SidebarView.swift   # pages / contents / search / bookmarks / notes
  Resources/
    AppIcon.icns        # bundled by scripts/make-app.sh (excluded from SPM)
Sources/PDFReaderKit/
  Models/
    PDFReaderState.swift  # document state, search, outline, annotations, themes
    AppTheme.swift        # System/Light/Dark/Monokai/Dark Pro
    HighlightColor.swift  # markup palette + annotation tools
    BookmarkStore.swift
    RecentFilesStore.swift
Sources/PDFReaderVerify/  # headless checks runnable without Xcode
Tests/PDFReaderKitTests/
scripts/
  make-app.sh        # assembles PDFReader.app + icon, ad-hoc signs
  make-dmg.sh        # builds the release DMG
  generate-icon.swift # regenerates the app icon
```

## Conventions

- Swift 6, `.swiftLanguageMode(.v5)`, macOS 14+ APIs only.
- `PDFReaderState` is `@MainActor`; keep PDFKit mutations on the main actor.
- Persist user prefs in `UserDefaults` under `com.pdfreader.*` keys and keep
  them backward compatible (add a migration path, don't silently drop values).
- UI strings: every toolbar/sidebar button needs `.help()` tooltip text and,
  for icon-only controls, an `.accessibilityLabel()`.
- No new third-party dependencies without discussion — stdlib + AppKit /
  PDFKit / SwiftUI only.
- `Sources/PDFReader/Resources/` is excluded from the SPM target in
  `Package.swift`; it is copied into the bundle by `scripts/make-app.sh`.
  Don't reference it via `Bundle.module`.

## Reporting issues

Open an issue with: macOS version, app version (or commit), a sample PDF
when possible, steps to reproduce, and expected vs. actual behavior.

## Releases

Maintainers cut releases by pushing a `v*` tag; CI builds, signs, and
publishes the DMG automatically. Don't commit binaries or DMGs.
