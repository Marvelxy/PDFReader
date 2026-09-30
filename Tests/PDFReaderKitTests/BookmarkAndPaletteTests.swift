import AppKit
import XCTest

@testable import PDFReaderKit

final class BookmarkAndPaletteTests: XCTestCase {
    func testHighlightPaletteHasNinePresetsPlusCustom() {
        XCTAssertEqual(HighlightColor.presets.count, 9)
        let names = Set(HighlightColor.presets.map { $0.displayName })
        XCTAssertEqual(names.count, 9)
        XCTAssertFalse(HighlightColor.presets.contains(.custom))
        XCTAssertEqual(HighlightColor(rawValue: "yellow"), .yellow)
    }

    @MainActor
    func testFavoriteRotationCyclesAndPersists() {
        UserDefaults.standard.removeObject(forKey: "com.pdfreader.highlightFavorites.v1")
        let state = PDFReaderState()
        XCTAssertEqual(state.favoriteColors, [.yellow, .green, .pink])
        state.toggleFavorite(.red)
        XCTAssertTrue(state.favoriteColors.contains(.red))
        state.highlightColor = .yellow
        state.cycleHighlightColor()
        XCTAssertEqual(state.highlightColor, .green)
        state.toggleFavorite(.yellow)
        state.toggleFavorite(.green)
        state.toggleFavorite(.pink)
        state.toggleFavorite(.red)
        XCTAssertEqual(state.favoriteColors, [.red])
        UserDefaults.standard.removeObject(forKey: "com.pdfreader.highlightFavorites.v1")
    }

    @MainActor
    func testCustomHighlightColorResolvesAndPersists() {
        UserDefaults.standard.removeObject(forKey: "com.pdfreader.highlightColor.v1")
        UserDefaults.standard.removeObject(forKey: "com.pdfreader.highlightCustomColor.v1")
        let state = PDFReaderState()
        state.highlightColor = .custom
        state.customHighlightColor = NSColor.magenta
        XCTAssertEqual(state.resolvedHighlightNSColor, NSColor.magenta)
        let reloaded = PDFReaderState()
        XCTAssertEqual(reloaded.highlightColor, .custom)
        XCTAssertEqual(reloaded.resolvedHighlightNSColor, NSColor.magenta)
        UserDefaults.standard.removeObject(forKey: "com.pdfreader.highlightColor.v1")
        UserDefaults.standard.removeObject(forKey: "com.pdfreader.highlightCustomColor.v1")
    }

    func testAnnotationModesCoverSelectMarkupAndNotes() {
        let modes = AnnotationMode.allCases.map { $0.rawValue }
        XCTAssertTrue(modes.contains("select"))
        XCTAssertTrue(modes.contains("highlight"))
        XCTAssertTrue(modes.contains("note"))
    }

    func testBookmarkStoreTogglesAndPersistsPerFile() {
        UserDefaults.standard.removeObject(forKey: "com.pdfreader.bookmarks.v1")
        let store = BookmarkStore()
        XCTAssertTrue(store.bookmarks.isEmpty)

        store.toggle(fileName: "a.pdf", pageIndex: 2)
        XCTAssertTrue(store.isBookmarked(fileName: "a.pdf", pageIndex: 2))
        XCTAssertEqual(store.bookmarks(for: "a.pdf").count, 1)
        XCTAssertTrue(store.bookmarks(for: "b.pdf").isEmpty)

        // A fresh instance reads the persisted JSON.
        let reloaded = BookmarkStore()
        XCTAssertTrue(reloaded.isBookmarked(fileName: "a.pdf", pageIndex: 2))

        reloaded.toggle(fileName: "a.pdf", pageIndex: 2)
        XCTAssertFalse(reloaded.isBookmarked(fileName: "a.pdf", pageIndex: 2))

        UserDefaults.standard.removeObject(forKey: "com.pdfreader.bookmarks.v1")
    }

    func testReadingLayoutsMapToDistinctDisplayModes() {
        let modes = ReadingLayout.allCases.map { $0.pdfDisplayMode.rawValue }
        XCTAssertEqual(Set(modes).count, ReadingLayout.allCases.count)
    }

    func testRecentFilesRecordDedupeCapAndPersist() {
        UserDefaults.standard.removeObject(forKey: "com.pdfreader.recentFiles.v1")
        let recents = RecentFilesStore()
        XCTAssertTrue(recents.items.isEmpty)
        let fileA = URL(fileURLWithPath: "/tmp/a.pdf")
        let fileB = URL(fileURLWithPath: "/tmp/b.pdf")
        recents.record(fileA)
        recents.record(fileB)
        XCTAssertEqual(recents.items.map(\.url), [fileB, fileA])
        recents.record(fileA)
        XCTAssertEqual(recents.items.map(\.url), [fileA, fileB])
        for i in 0 ..< 12 {
            recents.record(URL(fileURLWithPath: "/tmp/f\(i).pdf"))
        }
        XCTAssertEqual(recents.items.count, 10)
        XCTAssertEqual(RecentFilesStore().items.count, 10)
        recents.clear()
        XCTAssertTrue(RecentFilesStore().items.isEmpty)
        UserDefaults.standard.removeObject(forKey: "com.pdfreader.recentFiles.v1")

        let now = Date()
        XCTAssertEqual(RecentFile.ageDescription(for: now.addingTimeInterval(-10), now: now), "Just now")
        XCTAssertEqual(RecentFile.ageDescription(for: now.addingTimeInterval(-90), now: now), "1 min ago")
        XCTAssertFalse(RecentFile.ageDescription(for: now.addingTimeInterval(-74), now: now).contains("sec"))
    }
}
