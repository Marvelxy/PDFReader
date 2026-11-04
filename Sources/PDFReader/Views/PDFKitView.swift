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
        // `.colorInvert()` in dark themes, turning this + white pages dark.
        // Must be a fixed light color (semantic colors resolve dark under
        // `.preferredColorScheme(.dark)` and would invert back to light).
        pdfView.backgroundColor = state.usesDarkPages ? .white : .windowBackgroundColor
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
        // See makeNSView: white pre-invert -> black post-invert in dark themes.
        pdfView.backgroundColor = state.usesDarkPages ? .white : .windowBackgroundColor

        // Navigate only when state explicitly requests it (open, tab
        // switch, restore, toolbar page nav). Never derive navigation from
        // the live view page: PDFView reports its most-visible page
        // asynchronously during scrolling, so comparing against
        // `currentPageIndex` here fired stale `go(to:)`s that yanked the
        // view back mid-scroll and kept the toolbar/status page numbers
        // from updating.
        state.consumePendingNavigation(in: pdfView)
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
            // PDFKit posts these on the main thread; sync synchronously so
            // the toolbar page field and status bar update the same frame
            // the user scrolls (the previous one-frame-hop Task delayed the
            // update past SwiftUI's next updateNSView pass). The thread
            // check keeps assumeIsolated safe if PDFKit ever posts async.
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.state?.syncCurrentPageFromView(view)
                }
            } else {
                Task { @MainActor in
                    self.state?.syncCurrentPageFromView(view)
                }
            }
        }

        @objc func scaleChanged(_ note: Notification) {
            guard let view = note.object as? PDFView else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    if let s = self.state, view.scaleFactor != s.scaleFactor {
                        s.scaleFactor = view.scaleFactor
                    }
                }
            } else {
                Task { @MainActor in
                    if let s = self.state, view.scaleFactor != s.scaleFactor {
                        s.scaleFactor = view.scaleFactor
                    }
                }
            }
        }

        @objc func selectionChanged(_ note: Notification) {
            guard note.object is PDFView else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.state?.handleSelectionChange()
                }
            } else {
                Task { @MainActor in
                    self.state?.handleSelectionChange()
                }
            }
        }
    }
}

/// Thumbnail strip used in the sidebar. Renders page thumbnails in a lazy
/// stack so the current page can be highlighted with a user-chosen color
/// (PDFThumbnailView owns its selection color and offers no API for it).
/// Thumbnail size follows `state.thumbnailScale` (0.5...5.0, 1.0 = 72x96).
public struct PDFThumbnailStrip: View {
    @ObservedObject public var state: PDFReaderState

    public init(state: PDFReaderState) {
        self.state = state
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(0 ..< state.pageCount, id: \.self) { index in
                        ThumbnailCell(state: state, pageIndex: index)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .onAppear { scrollToCurrentPage(proxy) }
            .onChange(of: state.currentPageIndex) { _, _ in
                scrollToCurrentPage(proxy)
            }
            .onChange(of: state.fileURL) { _, _ in
                scrollToCurrentPage(proxy)
            }
        }
    }

    /// Keeps the current page visible, matching PDFThumbnailView's
    /// follow-the-document behavior.
    private func scrollToCurrentPage(_ proxy: ScrollViewProxy) {
        guard state.pageCount > 0 else { return }
        let index = min(max(0, state.currentPageIndex), state.pageCount - 1)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(index, anchor: .center)
            }
        }
    }
}

private struct ThumbnailCell: View {
    @ObservedObject var state: PDFReaderState
    let pageIndex: Int

    /// Size thumbnails are rendered at. Lags `thumbnailSize` slightly so a
    /// slider drag doesn't re-render every visible page at every step (the
    /// same reason the old PDFThumbnailView bridge debounced resizes).
    @State private var renderSize: NSSize = .zero
    @State private var resizeTask: Task<Void, Never>?

    private var isCurrent: Bool { state.currentPageIndex == pageIndex }

    private var thumbnailSize: NSSize {
        let scale = min(5.0, max(0.5, state.thumbnailScale))
        return NSSize(width: 72 * scale, height: 96 * scale)
    }

    private var imageSize: NSSize {
        renderSize == .zero ? thumbnailSize : renderSize
    }

    private var highlightColor: Color { state.pageHighlightSwiftUIColor }

    var body: some View {
        VStack(spacing: 4) {
            thumbnail
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isCurrent ? highlightColor.opacity(0.18) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            isCurrent ? highlightColor : Color.secondary.opacity(0.25),
                            lineWidth: isCurrent ? 2.5 : 0.5
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("\(pageIndex + 1)")
                .font(.caption2)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? highlightColor : Color.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            state.goToPage(index: pageIndex)
        }
        .help("Page \(pageIndex + 1)")
        .accessibilityLabel("Page \(pageIndex + 1)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .onAppear {
            renderSize = thumbnailSize
        }
        .onChange(of: thumbnailSize) { _, newSize in
            resizeTask?.cancel()
            resizeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                renderSize = newSize
            }
        }
        .onDisappear {
            resizeTask?.cancel()
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = thumbnailImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(
                    Image(systemName: "doc")
                        .foregroundStyle(.tertiary)
                )
        }
    }

    private var thumbnailImage: NSImage? {
        guard let doc = state.document else { return nil }
        return ThumbnailImageCache.image(
            document: doc,
            pageIndex: pageIndex,
            fileURL: state.fileURL,
            size: imageSize,
            revision: state.thumbnailRevision
        )
    }
}

/// Small in-memory cache so scrolling and page changes don't re-render
/// every visible thumbnail on each SwiftUI update pass.
@MainActor
private enum ThumbnailImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(
        document: PDFDocument,
        pageIndex: Int,
        fileURL: URL?,
        size: NSSize,
        revision: Int
    ) -> NSImage? {
        let key = "\(fileURL?.path ?? "untitled")#\(pageIndex)#\(Int(size.width))x\(Int(size.height))#\(revision)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let page = document.page(at: pageIndex) else { return nil }
        let image = page.thumbnail(of: size, for: .mediaBox)
        cache.setObject(image, forKey: key)
        return image
    }
}
