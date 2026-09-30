import AppKit
import PDFKit
import PDFReaderKit
import SwiftUI

/// SwiftUI wrapper around PDFKit's `PDFView`.
/// Keeps a weak back-reference in state so toolbar/sidebar actions
/// (zoom, search focus, annotations) can drive the live view.
public struct PDFKitView: NSViewRepresentable {
    @ObservedObject public var state: PDFReaderState

    public init(state: PDFReaderState) {
        self.state = state
    }

    public func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.delegate = context.coordinator
        pdfView.autoScales = state.autoScales
        pdfView.displayMode = state.layout.pdfDisplayMode
        pdfView.displaysPageBreaks = true
        pdfView.displayBox = .mediaBox
        // Keep the pre-invert color light: ContentView applies
        // `.colorInvert()` in night mode, turning this + white pages dark.
        // Must be a fixed light color (semantic colors resolve dark under
        // `.preferredColorScheme(.dark)` and would invert back to light).
        pdfView.backgroundColor = state.nightMode ? .white : .windowBackgroundColor
        pdfView.document = state.document
        state.pdfView = pdfView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
        return pdfView
    }

    public func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== state.document {
            pdfView.document = state.document
        }
        state.applyLayoutToView(pdfView)
        // See makeNSView: white pre-invert -> black post-invert in night mode.
        pdfView.backgroundColor = state.nightMode ? .white : .windowBackgroundColor

        // Keep the visible page in sync when sidebar/search drives navigation.
        if let doc = state.document,
           let current = pdfView.currentPage,
           doc.index(for: current) != state.currentPageIndex,
           let target = doc.page(at: state.currentPageIndex)
        {
            pdfView.go(to: target)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    @MainActor
    public final class Coordinator: NSObject, PDFViewDelegate {
        private weak var state: PDFReaderState?

        init(state: PDFReaderState) {
            self.state = state
        }

        @objc func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView else { return }
            Task { @MainActor in
                self.state?.syncCurrentPageFromView(view)
            }
        }

        @objc func scaleChanged(_ note: Notification) {
            guard let view = note.object as? PDFView else { return }
            Task { @MainActor in
                if let s = self.state, view.scaleFactor != s.scaleFactor {
                    s.scaleFactor = view.scaleFactor
                }
            }
        }

        @objc func selectionChanged(_ note: Notification) {
            guard note.object is PDFView else { return }
            Task { @MainActor in
                self.state?.handleSelectionChange()
            }
        }
    }
}

/// Thumbnail strip used in the sidebar. Separate representable because
/// `PDFThumbnailView` must share the same `PDFView` instance.
public struct PDFThumbnailStrip: NSViewRepresentable {
    @ObservedObject public var state: PDFReaderState

    public init(state: PDFReaderState) {
        self.state = state
    }

    public func makeNSView(context: Context) -> PDFThumbnailView {
        let thumbs = PDFThumbnailView()
        thumbs.thumbnailSize = NSSize(width: 72, height: 96)
        thumbs.backgroundColor = .clear
        return thumbs
    }

    public func updateNSView(_ thumbs: PDFThumbnailView, context: Context) {
        if thumbs.pdfView !== state.pdfView {
            thumbs.pdfView = state.pdfView
        }
    }
}
