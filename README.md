# PDFReader for Mac

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

Native macOS PDF reader built with SwiftUI + PDFKit as a Swift Package
(no Xcode project required — builds with `swift build` / `swift run`).

## Features (v1)

- **Basic viewing** — open PDFs, continuous / single / two-up layouts,
  zoom in/out + auto-fit, page navigation, thumbnail strip.
- **Search + outline** — full-text search with match list + highlight,
  table-of-contents navigation, per-file bookmarks (persisted).
- **Annotations** — highlight, underline, strikethrough, sticky notes with
  a switchable palette (yellow / green / blue / pink / orange / purple /
  red / teal / gray) plus an editable custom color (persisted).
  Build your own rotation shortlist (star colors in the color menu) and
  cycle through it with the Next Color button (⇧⌘C).
  Highlights apply automatically once a text selection settles, and the
  color advances to the next rotation color after every highlight.
  **Undo / redo** for annotation changes (⌘Z / ⇧⌘Z).
  Annotation list inspector with jump-to + delete.
- **Saving** — **Save** (⌘S) writes annotations back into the opened PDF;
  **Save Copy** exports an annotated duplicate.
- **Recents** — the Open menu keeps an Open Recent list (with Clear Menu);
  the welcome screen shows your recent files with relative dates. Missing
  files are reported and dropped on open.
- **Reading modes** — layout menu, book mode, RTL, night background,
  presentation (full-screen).
- **Settings** — ⌘, opens Settings; toggle "Remember where I left off
  in each file" (on by default) to control last-position restore.
- **Updates** — Help → Check for Updates… compares the build's version
  against the latest GitHub release and offers the DMG download.
- **Themes** — system / light / dark / sepia-style page themes from the
  toolbar; preference is persisted.

## Requirements

- macOS 14+, Intel or Apple Silicon.
- For development: Swift 6 toolchain (Command Line Tools is enough).

## Install

1. Download `PDFReader-vX.Y.Z-macOS-universal.dmg` from
   [Releases](https://github.com/Marvelxy/PDFReader/releases).
2. Open the DMG and drag **PDFReader** into **Applications**
   (or run it straight from the DMG to try it out).
3. First launch: the app is ad-hoc signed, so Gatekeeper may block it.
   Right-click **PDFReader** → **Open** → **Open** once — afterwards it
   launches normally. (Signing with a Developer ID + notarization removes
   this step; see `scripts/`.)
4. To uninstall: drag PDFReader from Applications to Trash, and optionally
   delete its preferences (`~/Library/Preferences/com.example.pdfreader.plist`).

## Build & run

```sh
cd PDFReader
swift build
swift run PDFReader

# Open a sample immediately:
PDFREADER_SAMPLE=~/Downloads/sample.pdf swift run PDFReader
```

For normal use, run it as a bundled app (required on macOS Tahoe for
cursors — resize handle, I-beam, etc. — to render; a raw `swift run`
binary is stuck with the arrow pointer):

```sh
scripts/make-app.sh [debug|release]
open .build/app/PDFReader.app
```

## Verification

```sh
swift run PDFReaderVerify   # headless checks, works with Command Line Tools
swift test                  # XCTest suite, requires full Xcode
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, branch workflow,
verification (`swift build` / `swift run PDFReaderVerify` / `swift test`),
and code conventions.

## Project layout

```
Sources/PDFReader/
  PDFReaderApp.swift      # @main SwiftUI App
  Models/
    PDFReaderState.swift  # document state, search, outline, annotations
    HighlightColor.swift  # switchable markup palette + tools
    BookmarkStore.swift   # persisted per-file bookmarks
  Views/
    ContentView.swift     # split view, toolbar, status bar
    PDFKitView.swift      # PDFView + PDFThumbnailView bridges
    SidebarView.swift     # pages / contents / search / bookmarks / notes
    AboutView.swift       # App menu → About
    SettingsView.swift    # App menu → Settings… (⌘,)
    Services/UpdateChecker.swift  # Help → Check for Updates…
```

## Releasing

Releases are cut from version tags:

```sh
git tag vX.Y.Z && git push origin vX.Y.Z
```

CI builds the universal binary + DMG, stamps the app version from the tag
(`CFBundleShortVersionString`), and creates the GitHub release. Don't
create the GitHub release manually first — `gh release create` in CI
fails if one with the same tag name already exists.

If `git push` fails mid-upload of the icon resources with
`send-pack: unexpected disconnect`, raise the HTTP post buffer:

```sh
git config http.postBuffer 524288000
```

## Notes

- PDFKit does the heavy lifting (`PDFDocument`, `PDFView`, `PDFThumbnailView`,
  `PDFSelection`, `PDFAnnotation`).
- Highlight colors map to `NSColor` so saved PDFs show the same color
  in Preview / other readers.
- Night mode darkens the window + viewer background. True per-page
  dark rendering would need custom page drawing — left for v2.

## License

Copyright (c) 2026 Marvelous Akpotu.

This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation, version 3. See [LICENSE](LICENSE) for the full
text — distributed modifications must stay under the GPL.
