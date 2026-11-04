import AppKit
import SwiftUI
import XCTest

@testable import PDFReaderKit

final class ThemeAndSidebarTests: XCTestCase {
    @MainActor
    func testAppThemeCasesCoverLightDarkAndPro() {
        let names = Set(AppTheme.allCases.map { $0.displayName })
        XCTAssertTrue(names.contains("Light"))
        XCTAssertTrue(names.contains("Dark"))
        XCTAssertTrue(names.contains("Monokai Light"))
        XCTAssertTrue(names.contains("Monokai Dark"))
        XCTAssertTrue(names.contains("Dark Pro"))
    }

    @MainActor
    func testAppThemeDarkPagesAndSchemes() {
        XCTAssertFalse(AppTheme.light.invertsPages)
        XCTAssertTrue(AppTheme.dark.invertsPages)
        XCTAssertFalse(AppTheme.monokaiLight.invertsPages)
        XCTAssertTrue(AppTheme.monokaiDark.invertsPages)
        XCTAssertTrue(AppTheme.darkPro.invertsPages)
        XCTAssertEqual(AppTheme.light.preferredColorScheme, .light)
        XCTAssertEqual(AppTheme.dark.preferredColorScheme, .dark)
        XCTAssertNil(AppTheme.system.preferredColorScheme)
    }

    @MainActor
    func testAppThemePersistsAcrossRelaunch() {
        UserDefaults.standard.removeObject(forKey: "com.pdfreader.appTheme.v1")
        let state = PDFReaderState()
        state.appTheme = .monokaiDark
        XCTAssertEqual(PDFReaderState().appTheme, .monokaiDark)
        state.appTheme = .system
        UserDefaults.standard.removeObject(forKey: "com.pdfreader.appTheme.v1")
    }

    @MainActor
    func testThumbnailZoomClampsAndHelpers() {
        let state = PDFReaderState()
        state.thumbnailScale = 10
        XCTAssertEqual(state.thumbnailScale, 5.0)
        state.thumbnailScale = 0.1
        XCTAssertEqual(state.thumbnailScale, 0.5)
        state.resetThumbnailZoom()
        XCTAssertEqual(state.thumbnailScale, 1.0)
        state.zoomThumbnailsIn()
        XCTAssertEqual(state.thumbnailScale, 1.25)
        state.zoomThumbnailsOut()
        XCTAssertEqual(state.thumbnailScale, 1.0)
    }

    @MainActor
    func testLegacyNightModeAliasMapsToTheme() {
        let state = PDFReaderState()
        state.appTheme = .light
        XCTAssertFalse(state.nightMode)
        XCTAssertFalse(state.usesDarkPages)
        state.nightMode = true
        XCTAssertEqual(state.appTheme, .dark)
        XCTAssertTrue(state.usesDarkPages)
    }

    @MainActor
    func testReadingProgressTracksCurrentPage() {
        let state = PDFReaderState()
        XCTAssertEqual(state.readingProgress, 0)
        XCTAssertEqual(state.readingPercentage, 0)

        state.pageCount = 10
        state.currentPageIndex = 0
        XCTAssertEqual(state.readingPercentage, 0)
        state.currentPageIndex = 4
        XCTAssertEqual(state.readingProgress, 4.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(state.readingPercentage, 44)
        state.currentPageIndex = 9
        XCTAssertEqual(state.readingPercentage, 100)
    }

    @MainActor
    func testPageHighlightDefaultsToBlueAndPersists() {
        UserDefaults.standard.removeObject(forKey: "com.pdfreader.pageHighlightColor.v1")
        let state = PDFReaderState()
        let defaultComponents = state.pageHighlightColor.usingColorSpace(.sRGB)
        XCTAssertNotNil(defaultComponents)
        XCTAssertGreaterThan(defaultComponents?.blueComponent ?? 0, 0.8)
        XCTAssertGreaterThan(defaultComponents?.blueComponent ?? 0, defaultComponents?.redComponent ?? 1)

        state.pageHighlightColor = NSColor(srgbRed: 0.9, green: 0.3, blue: 0.2, alpha: 1.0)
        let reloaded = PDFReaderState().pageHighlightColor.usingColorSpace(.sRGB)
        XCTAssertEqual(reloaded?.redComponent ?? 0, 0.9, accuracy: 0.001)
        XCTAssertEqual(reloaded?.greenComponent ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(reloaded?.blueComponent ?? 0, 0.2, accuracy: 0.001)

        UserDefaults.standard.removeObject(forKey: "com.pdfreader.pageHighlightColor.v1")
    }
}
