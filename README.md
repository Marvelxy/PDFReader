# PDFReader for Mac

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

Native macOS PDF reader built with SwiftUI + PDFKit as a Swift Package
(no Xcode project required — builds with `swift build` / `swift run`).

## Features (v1)

- **Basic viewing** — open PDFs, continuous / single / two-up layouts,
  zoom in/out + auto-fit, page navigation, thumbnail strip.
- **Reading progress** — the status bar shows the current page plus the
  percentage of the document read, updated as you scroll.
- **Customizable page highlight** — the current page in the Pages sidebar
  is highlighted in blue by default; pick any color from the swatch in the
  thumbnail toolbar (persisted).
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
  Annotation list inspector with jump-to, **recolor existing highlights**,
  and delete.
- **Library** — a full-page library (⌘L) groups opened books into
  **Currently reading**, **Want to read** and **Finished**. Every book shows
  a first-page cover and title plus how much you've read; switch between
  list and grid views. Move books between shelves with the row menu,
  context menu, or drag and drop. Shelves, layout, and progress persist.
- **Saving** — **Save** (⌘S) writes annotations back into the opened PDF;
  **Save Copy** exports an annotated duplicate.
- **Printing** — **File → Print…** (⌘P) prints through the system print
  panel, so you can pick page ranges, scale, and include annotations.
- **Recents** — the Open menu keeps an Open Recent list (with Clear Menu);
  the welcome screen shows your recent files with relative dates. Missing
  files are reported and dropped on open.
- **Reading modes** — layout menu, book mode, RTL, night background,
  presentation (full-screen).
- **Tabs + session restore** — open multiple PDFs as tabs in the tab bar
  (⌘T / + button); click to switch, × to close, drag a tab sideways and it
  slides live under the pointer while the other tabs spring out of the way;
  release to drop it in place (the active document never reloads while
  reordering).
  Switching back to a tab returns to the exact section of the page you
  left (not just the page top); quitting and relaunching reopens the
  same tabs with each file back on the page you left it.
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

### From released DMG (recommended)
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

### From source (build + copy to Applications)
1. Clone the repo and install dependencies:
   ```sh
   git clone https://github.com/Marvelxy/PDFReader.git
   cd PDFReader
   swift build
   ```
2. Build the bundled app (required for macOS Tahoe+ cursor support):
   ```sh
   scripts/make-app.sh debug
   ```
3. Copy the app to Applications:
   ```sh
   cp -R .build/app/PDFReader.app /Applications/
   ```
4. First launch: right-click **PDFReader** → **Open** → **Open** once to
   overcome Gatekeeper's ad-hoc signature. (Or sign with a Developer ID
   + notarize for seamless launching.)

### From source (swift run only)
Running `swift run PDFReader` launches a headless binary without the
app bundle — useful for quick testing but **not** recommended for daily
use because cursor styles and other AppKit-dependent features won't
render correctly on macOS 15+.

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

> **Important:** `swift build` only updates `.build/debug/PDFReader`; it
> does **not** refresh an existing `.build/app/PDFReader.app`. After code
> changes, rerun `scripts/make-app.sh` and relaunch the app — otherwise
> you'll keep running the old build (and won't see new menu items,
> toolbar buttons, etc.).

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
    LibraryStore.swift    # persisted reading shelves + progress
  Views/
    ContentView.swift     # split view, toolbar, status bar
    PDFKitView.swift      # PDFView + PDFThumbnailView bridges
    SidebarView.swift     # pages / contents / search / bookmarks / notes
    LibraryView.swift     # library page (shelves + progress)
    AboutView.swift       # App menu → About
    SettingsView.swift    # App menu → Settings… (⌘,)
    Services/UpdateChecker.swift  # Help → Check for Updates…
```

## Releasing

Releases are automatic when changes merge to `main` (or `master`). CI runs
the build, verification checks and tests, bumps the patch version from the
latest `v*` tag (for example `v1.3.3` → `v1.3.4`), creates and pushes the
tag, builds the universal binary + DMG, and publishes the GitHub release.

For a major or minor release, push the tag yourself; CI builds and
publishes that exact tag:

```sh
git tag vX.Y.Z && git push origin vX.Y.Z
```

If a release already exists for the tag, CI re-uploads the DMG instead of
failing, so re-running a workflow is safe. Re-runs reuse the tag already
pointing at the merge commit instead of bumping the version again.

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
