import PDFKit
import XCTest

@testable import PDFReaderKit

@MainActor
final class PDFReaderStateTests: XCTestCase {
    func testOpenInvalidURLFailsGracefully() {
        let state = PDFReaderState()
        let ok = state.open(url: URL(fileURLWithPath: "/nonexistent/missing.pdf"))
        XCTAssertFalse(ok)
        XCTAssertNil(state.document)
        XCTAssertEqual(state.pageCount, 0)
    }

    func testGeneratedPDFOpensWithCorrectPageCount() throws {
        let url = try makeSamplePDF(pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let state = PDFReaderState()
        XCTAssertTrue(state.open(url: url))
        XCTAssertEqual(state.pageCount, 3)
        XCTAssertFalse(state.outlineNodes.isEmpty)
    }

    func testPageNavigationClampsToValidRange() throws {
        let url = try makeSamplePDF(pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let state = PDFReaderState()
        _ = state.open(url: url)
        state.goToPage(index: 10, viaView: false)
        XCTAssertEqual(state.currentPageIndex, 2)
        state.goToPage(index: -5, viaView: false)
        XCTAssertEqual(state.currentPageIndex, 0)
        state.goToPage(index: 1, viaView: false)
        state.goToNextPage()
        // No live PDFView attached, so navigation clamps at the last page.
        XCTAssertEqual(state.currentPageIndex, 2)
    }

    func testSearchFindsGeneratedText() throws {
        let url = try makeSamplePDF(pages: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let state = PDFReaderState()
        _ = state.open(url: url)
        state.searchQuery = "Hello PDFReader"
        state.runSearch()
        XCTAssertFalse(state.searchHits.isEmpty)
        state.clearSearch()
        XCTAssertTrue(state.searchHits.isEmpty)
    }

    // MARK: - Helpers

    /// Builds a tiny multi-page PDF on disk with real (searchable) text.
    private func makeSamplePDF(pages: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFReaderTest-\(UUID().uuidString).pdf")
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
}
