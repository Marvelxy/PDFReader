import AppKit
import Foundation
import PDFKit
import PDFReaderKit

/// Headless verification for environments without Xcode (no XCTest).
/// Run with `swift run PDFReaderVerify`. Exits non-zero on any failure.

@MainActor
func check(_ condition: Bool, _ label: String, failures: inout Int) {
    if condition {
        print("PASS: \(label)")
    } else {
        print("FAIL: \(label)")
        failures += 1
    }
}

@MainActor
func makeSamplePDF(pages: Int) throws -> URL {
    // Draw real text into a CG PDF context so PDFKit's findString works.
    // (Free-text annotation contents are not indexed by findString.)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("PDFReaderVerify-\(UUID().uuidString).pdf")
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let ctx = withUnsafePointer(to: &mediaBox, { mediaBoxPtr in
        CGContext(url as CFURL, mediaBox: mediaBoxPtr, nil)
    }) else {
        throw CocoaError(.fileWriteUnknown)
    }
    for i in 0 ..< pages {
        ctx.beginPDFPage(nil as CFDictionary?)
        let gfx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gfx
        let str = NSAttributedString(
            string: "Hello PDFReader page \(i + 1)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 24),
                .foregroundColor: NSColor.black,
            ]
        )
        str.draw(at: NSPoint(x: 72, y: 650))
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
    }
    ctx.closePDF()

    // Add an outline so the Contents tab has something to show.
    if let doc = PDFDocument(url: url) {
        let root = PDFOutline()
        doc.outlineRoot = root
        for i in 0 ..< pages {
            if let page = doc.page(at: i) {
                let dest = PDFDestination(page: page, at: NSPoint(x: 0, y: 0))
                let child = PDFOutline()
                child.label = "Chapter \(i + 1)"
                child.destination = dest
                root.insertChild(child, at: root.numberOfChildren)
            }
        }
        doc.write(to: url)
    }
    return url
}

@MainActor
func run() async -> Int {
    var failures = 0

    check(HighlightColor.presets.count == 9, "nine preset highlight colors", failures: &failures)
    check(
        Set(HighlightColor.presets.map { $0.displayName }).count == 9,
        "preset color names are distinct",
        failures: &failures
    )
    check(!HighlightColor.presets.contains(.custom), "custom is not a preset", failures: &failures)
    // Custom color resolves for painting and survives reload.
    UserDefaults.standard.removeObject(forKey: "com.pdfreader.highlightColor.v1")
    UserDefaults.standard.removeObject(forKey: "com.pdfreader.highlightCustomColor.v1")
    do {
        let customState = PDFReaderState()
        customState.highlightColor = .custom
        customState.customHighlightColor = NSColor.magenta
        check(customState.resolvedHighlightNSColor == NSColor.magenta, "custom color resolves", failures: &failures)
        let reloadedPrefs = PDFReaderState()
        check(reloadedPrefs.highlightColor == .custom, "highlight choice persists", failures: &failures)
        check(reloadedPrefs.resolvedHighlightNSColor == NSColor.magenta, "custom color persists", failures: &failures)
    }
    UserDefaults.standard.removeObject(forKey: "com.pdfreader.highlightColor.v1")
    UserDefaults.standard.removeObject(forKey: "com.pdfreader.highlightCustomColor.v1")
    // Favorites rotation: toggle, cycle with wrap, last-one guard, persist.
    UserDefaults.standard.removeObject(forKey: "com.pdfreader.highlightFavorites.v1")
    do {
        let fav = PDFReaderState()
        check(fav.favoriteColors == [.yellow, .green, .pink], "default rotation is yellow/green/pink", failures: &failures)
        fav.toggleFavorite(.red)
        check(fav.favoriteColors == [.yellow, .green, .pink, .red], "toggle adds to rotation", failures: &failures)
        fav.toggleFavorite(.green)
        check(!fav.favoriteColors.contains(.green), "toggle removes from rotation", failures: &failures)
        fav.highlightColor = .yellow
        fav.cycleHighlightColor()
        check(fav.highlightColor == .pink, "cycle advances rotation", failures: &failures)
        fav.cycleHighlightColor()
        check(fav.highlightColor == .red, "cycle continues rotation", failures: &failures)
        fav.cycleHighlightColor()
        check(fav.highlightColor == .yellow, "cycle wraps rotation", failures: &failures)
        fav.highlightColor = .blue
        fav.cycleHighlightColor()
        check(fav.highlightColor == .yellow, "cycle from outside jumps to first", failures: &failures)
        let solo = PDFReaderState()
        solo.favoriteColors = [.teal]
        solo.toggleFavorite(.teal)
        check(solo.favoriteColors == [.teal], "rotation keeps last color", failures: &failures)
        fav.favoriteColors = [.blue, .custom]
        check(PDFReaderState().favoriteColors == [.blue, .custom], "rotation persists", failures: &failures)
    }
    UserDefaults.standard.removeObject(forKey: "com.pdfreader.highlightFavorites.v1")
    // Recents: newest-first, bump-on-reopen, cap, persist, clear.
    UserDefaults.standard.removeObject(forKey: "com.pdfreader.recentFiles.v1")
    do {
        let recents = RecentFilesStore()
        check(recents.items.isEmpty, "recents start empty", failures: &failures)
        let fileA = URL(fileURLWithPath: "/tmp/a.pdf")
        let fileB = URL(fileURLWithPath: "/tmp/b.pdf")
        recents.record(fileA)
        recents.record(fileB)
        check(recents.items.map(\.url) == [fileB, fileA], "recents newest first", failures: &failures)
        recents.record(fileA)
        check(recents.items.map(\.url) == [fileA, fileB], "reopen bumps to top without dupes", failures: &failures)
        for i in 0 ..< 12 {
            recents.record(URL(fileURLWithPath: "/tmp/f\(i).pdf"))
        }
        check(recents.items.count == 10, "recents capped at 10", failures: &failures)
        check(recents.items.first?.name == "f11.pdf", "cap keeps newest", failures: &failures)
        check(RecentFilesStore().items.count == 10, "recents persist", failures: &failures)
        recents.remove(URL(fileURLWithPath: "/tmp/f11.pdf"))
        check(!recents.items.map(\.name).contains("f11.pdf"), "remove drops file", failures: &failures)
        recents.clear()
        check(recents.items.isEmpty && RecentFilesStore().items.isEmpty, "clear empties recents", failures: &failures)
        // Age labels never show seconds ("1 min ago", not "1 min, 14 secs").
        let now = Date()
        check(RecentFile.ageDescription(for: now.addingTimeInterval(-10), now: now) == "Just now", "age just now", failures: &failures)
        check(RecentFile.ageDescription(for: now.addingTimeInterval(-90), now: now) == "1 min ago", "age minutes", failures: &failures)
        check(RecentFile.ageDescription(for: now.addingTimeInterval(-(5 * 60 + 30)), now: now) == "5 min ago", "age drops seconds", failures: &failures)
        check(RecentFile.ageDescription(for: now.addingTimeInterval(-3_600), now: now) == "1 hr ago", "age hours", failures: &failures)
        check(RecentFile.ageDescription(for: now.addingTimeInterval(-86_400), now: now) == "1 day ago", "age days", failures: &failures)
        let oldAge = RecentFile.ageDescription(for: now.addingTimeInterval(-10 * 86_400), now: now)
        check(!oldAge.contains("sec") && !oldAge.contains("ago"), "old files show calendar date", failures: &failures)
    }
    UserDefaults.standard.removeObject(forKey: "com.pdfreader.recentFiles.v1")
    check(
        AnnotationMode.allCases.map { $0.rawValue }.contains("highlight"),
        "annotation modes include highlight",
        failures: &failures
    )
    check(
        Set(ReadingLayout.allCases.map { $0.pdfDisplayMode.rawValue }).count == ReadingLayout.allCases.count,
        "reading layouts map to distinct PDFKit display modes",
        failures: &failures
    )

    UserDefaults.standard.removeObject(forKey: "com.pdfreader.bookmarks.v1")
    let store = BookmarkStore()
    store.toggle(fileName: "a.pdf", pageIndex: 2)
    check(store.isBookmarked(fileName: "a.pdf", pageIndex: 2), "bookmark toggle adds", failures: &failures)
    check(BookmarkStore().isBookmarked(fileName: "a.pdf", pageIndex: 2), "bookmark persists", failures: &failures)
    store.toggle(fileName: "a.pdf", pageIndex: 2)
    check(!store.isBookmarked(fileName: "a.pdf", pageIndex: 2), "bookmark toggle removes", failures: &failures)
    UserDefaults.standard.removeObject(forKey: "com.pdfreader.bookmarks.v1")

    let bad = PDFReaderState()
    check(!bad.open(url: URL(fileURLWithPath: "/nonexistent/missing.pdf")), "invalid URL fails gracefully", failures: &failures)

    do {
        let url = try makeSamplePDF(pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let state = PDFReaderState()
        check(state.open(url: url), "generated PDF opens", failures: &failures)
        check(state.pageCount == 3, "page count is 3", failures: &failures)
        check(!state.outlineNodes.isEmpty, "outline parsed", failures: &failures)
        state.goToPage(index: 99, viaView: false)
        check(state.currentPageIndex == 2, "page navigation clamps high", failures: &failures)
        state.goToPage(index: -1, viaView: false)
        check(state.currentPageIndex == 0, "page navigation clamps low", failures: &failures)
        state.searchQuery = "Hello PDFReader"
        state.runSearch()
        check(!state.searchHits.isEmpty, "search finds generated text", failures: &failures)
        // Highlight regression: a real-text selection must produce an
        // annotation; an empty selection must prompt, not apply.
        state.annotationMode = .highlight
        let panel = PDFView()
        panel.document = state.document
        state.pdfView = panel
        if let first = state.searchHits.first {
            panel.currentSelection = first.selection
            let rowsBefore = state.annotationRows.count
            state.annotateCurrentSelection()
            check(state.annotationRows.count > rowsBefore, "highlight applies to text selection", failures: &failures)
        } else {
            print("FAIL: no hit available to highlight")
            failures += 1
        }
        panel.currentSelection = nil
        let rowsBeforeEmpty = state.annotationRows.count
        state.annotateCurrentSelection()
        check(state.annotationRows.count == rowsBeforeEmpty, "empty selection adds no annotation", failures: &failures)
        check(state.statusMessage.contains("Select some text"), "empty selection prompts for text", failures: &failures)
        // Auto-annotate: a settled selection applies on its own (0.5s debounce).
        if let auto = state.searchHits.first {
            panel.currentSelection = auto.selection
            let autoBefore = state.annotationRows.count
            state.handleSelectionChange()
            try? await Task.sleep(nanoseconds: 700_000_000)
            check(state.annotationRows.count > autoBefore, "selection change auto-applies highlight", failures: &failures)
            check(panel.currentSelection == nil, "auto-apply clears the selection", failures: &failures)
        } else {
            print("FAIL: no hit available to auto-annotate")
            failures += 1
        }
        // Picking a tool with text selected applies immediately.
        if let switched = state.searchHits.first {
            panel.currentSelection = switched.selection
            state.annotationMode = .underline
            let switchBefore = state.annotationRows.count
            state.applyToCurrentSelectionIfPresent()
            check(state.annotationRows.count > switchBefore, "tool switch applies to existing selection", failures: &failures)
        } else {
            print("FAIL: no hit available for tool-switch check")
            failures += 1
        }
        // Auto-advance: every applied highlight moves to the next rotation color.
        state.favoriteColors = [.yellow, .pink]
        state.annotationMode = .highlight
        state.highlightColor = .yellow
        if let adv = state.searchHits.first {
            panel.currentSelection = adv.selection
            let advBefore = state.annotationRows.count
            state.handleSelectionChange()
            try? await Task.sleep(nanoseconds: 700_000_000)
            check(state.annotationRows.count > advBefore, "auto highlight applies for advance", failures: &failures)
            check(state.highlightColor == .pink, "color advances after highlight", failures: &failures)
            check(state.statusMessage.contains("Next up: Pink"), "status names next color", failures: &failures)
            panel.currentSelection = adv.selection
            state.handleSelectionChange()
            try? await Task.sleep(nanoseconds: 700_000_000)
            check(state.highlightColor == .yellow, "advance wraps rotation", failures: &failures)
        } else {
            print("FAIL: no hit available for advance checks")
            failures += 1
        }
        // No advance when nothing applied; none with a single favorite.
        state.highlightColor = .pink
        panel.currentSelection = nil
        state.annotateCurrentSelection()
        check(state.highlightColor == .pink, "no advance without selection", failures: &failures)
        state.favoriteColors = [.teal]
        state.highlightColor = .teal
        if let adv2 = state.searchHits.first {
            let soloBefore = state.annotationRows.count
            panel.currentSelection = adv2.selection
            state.handleSelectionChange()
            try? await Task.sleep(nanoseconds: 700_000_000)
            check(state.annotationRows.count > soloBefore, "single favorite still applies", failures: &failures)
            check(state.highlightColor == .teal, "single favorite does not advance", failures: &failures)
            check(!state.statusMessage.contains("Next up"), "no next-up with single favorite", failures: &failures)
        } else {
            print("FAIL: no hit available for single-favorite check")
            failures += 1
        }
        // The suppression flag in focusCurrentHit relies on PDFView posting
        // selection changes synchronously — prove that assumption headless.
        final class FiredBox: @unchecked Sendable { var fired = false }
        let firedBox = FiredBox()
        let token = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.PDFViewSelectionChanged,
            object: panel,
            queue: nil
        ) { _ in firedBox.fired = true }
        panel.currentSelection = state.searchHits.first?.selection
        check(firedBox.fired, "selection change posts synchronously", failures: &failures)
        NotificationCenter.default.removeObserver(token)
        // Focusing a search hit must NOT auto-annotate, neither at once
        // nor after the debounce window (would reveal async delivery).
        let focusBefore = state.annotationRows.count
        state.searchQuery = "Hello PDFReader"
        state.runSearch()
        check(state.annotationRows.count == focusBefore, "search focus does not auto-annotate", failures: &failures)
        try? await Task.sleep(nanoseconds: 800_000_000)
        check(state.annotationRows.count == focusBefore, "search focus stays un-annotated", failures: &failures)
        // Undo / redo round-trip for add and remove.
        if let undoHit = state.searchHits.first {
            panel.currentSelection = undoHit.selection
            state.annotationMode = .highlight
            let undoBase = state.annotationRows.count
            state.annotateCurrentSelection()
            let undoTop = state.annotationRows.count
            check(undoTop > undoBase && state.canUndo, "annotate is undoable", failures: &failures)
            state.undo()
            check(state.annotationRows.count == undoBase, "undo removes added annotation", failures: &failures)
            check(state.canRedo, "can redo after undo", failures: &failures)
            state.redo()
            check(state.annotationRows.count == undoTop, "redo restores annotation", failures: &failures)
            if let row = state.annotationRows.first {
                state.removeAnnotation(row)
                check(state.annotationRows.count == undoTop - 1, "remove drops annotation", failures: &failures)
                state.undo()
                check(state.annotationRows.count == undoTop, "undo restores removed annotation", failures: &failures)
                state.redo()
                check(state.annotationRows.count == undoTop - 1, "redo re-removes annotation", failures: &failures)
            } else {
                print("FAIL: no annotation row to remove")
                failures += 1
            }
        } else {
            print("FAIL: no hit available for undo checks")
            failures += 1
        }
        // Save writes annotations back into the opened file.
        check(state.save(), "save writes back to file", failures: &failures)
        let reopenedFile = PDFReaderState()
        check(reopenedFile.open(url: url), "reopens saved file", failures: &failures)
        check(!reopenedFile.annotationRows.isEmpty, "saved annotations persist on disk", failures: &failures)
        check(!PDFReaderState().save(), "save with no document fails gracefully", failures: &failures)
        state.clearSearch()
        check(state.searchHits.isEmpty, "clear search empties hits", failures: &failures)
    } catch {
        print("FAIL: sample PDF setup threw \(error)")
        failures += 1
    }

    return failures
}

let failures = await run()
if failures > 0 {
    print("\(failures) check(s) FAILED")
    exit(1)
} else {
    print("All PDFReaderVerify checks passed.")
}
