import AppKit
import Combine
import PDFKit
import SwiftUI

/// Outline node wrapper so SwiftUI lists get Identifiable + indentation level.
public struct PDFOutlineNode: Identifiable {
    public let id = UUID()
    public let outline: PDFOutline
    public let level: Int
    public var label: String { outline.label ?? "Untitled" }
    public var destinationPageIndex: Int? {
        guard let dest = outline.destination,
              let page = dest.page else { return nil }
        return outline.document?.index(for: page)
    }
}

/// Single search hit with page index for the results list.
public struct PDFSearchHit: Identifiable {
    public let id = UUID()
    public let selection: PDFSelection
    public let pageIndex: Int
    public var preview: String {
        let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(text.prefix(120))
    }
}

/// Annotation row for the Annotations inspector tab.
public struct PDFAnnotationRow: Identifiable {
    public let id = UUID()
    public let annotation: PDFAnnotation
    public let pageIndex: Int
    public var typeLabel: String { annotation.type ?? "Markup" }
    public var contents: String { annotation.contents ?? "" }
}

/// Reading layout options exposed in the toolbar.
public enum ReadingLayout: String, CaseIterable, Identifiable {
    case singleContinuous
    case singlePage
    case twoUpContinuous
    case twoUp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .singleContinuous: return "Continuous"
        case .singlePage: return "Single Page"
        case .twoUpContinuous: return "Two Pages Continuous"
        case .twoUp: return "Two Pages"
        }
    }

    public var pdfDisplayMode: PDFDisplayMode {
        switch self {
        case .singleContinuous: return .singlePageContinuous
        case .singlePage: return .singlePage
        case .twoUpContinuous: return .twoUpContinuous
        case .twoUp: return .twoUp
        }
    }
}

/// Central document state shared by the viewer, sidebar and toolbar.
@MainActor
public final class PDFReaderState: ObservableObject {
    // MARK: - Tab management

    /// URLs of all open PDF tabs.
    @Published public var tabURLs: [URL] = [] {
        didSet { saveSession() }
    }

    /// Index of the currently active tab.
    @Published public var activeTabIndex: Int = 0 {
        didSet {
            if tabURLs.isEmpty { activeTabIndex = 0 }
            else if activeTabIndex >= tabURLs.count { activeTabIndex = tabURLs.count - 1 }
            else if activeTabIndex < 0 { activeTabIndex = 0 }
            saveSession()
        }
    }

    // MARK: - Current tab document state (always reflects active tab)

    @Published public var document: PDFDocument?
    @Published public var fileURL: URL?
    public var fileName: String { fileURL?.lastPathComponent ?? "No document" }

    @Published public var currentPageIndex: Int = 0
    @Published public var pageCount: Int = 0

    @Published public var scaleFactor: CGFloat = 1.0
    @Published public var autoScales: Bool = true

    @Published public var layout: ReadingLayout = .singleContinuous
    @Published public var displaysAsBook: Bool = false
    @Published public var displaysRTL: Bool = false

    @Published public var searchQuery: String = ""
    @Published public var searchHits: [PDFSearchHit] = []
    @Published public var currentHitIndex: Int = 0
    @Published public var isSearching: Bool = false

    @Published public var outlineNodes: [PDFOutlineNode] = []
    @Published public var annotationRows: [PDFAnnotationRow] = []

    @Published public var annotationMode: AnnotationMode = .select
    @Published public var highlightColor: HighlightColor = .yellow {
        didSet { saveHighlightPrefs() }
    }
    /// User-edited color used when `highlightColor == .custom`. Persisted.
    /// Normalized to sRGB so in-memory and reloaded values always match.
    @Published public var customHighlightColor: NSColor = NSColor(red: 1.0, green: 0.2, blue: 0.6, alpha: 1.0) {
        didSet {
            if customHighlightColor.colorSpace != .sRGB,
               let converted = customHighlightColor.usingColorSpace(.sRGB)
            {
                // Terminates: the converted value is sRGB, so the guard
                // fails on re-entry even if didSet re-fires.
                customHighlightColor = converted
            }
            saveHighlightPrefs()
        }
    }

    /// User-selected shortlist cycled by "Next color", in order.
    @Published public var favoriteColors: [HighlightColor] = [.yellow, .green, .pink] {
        didSet { saveHighlightPrefs() }
    }

    /// The color markup tools actually paint with.
    public var resolvedHighlightNSColor: NSColor {
        highlightColor == .custom ? customHighlightColor : highlightColor.nsColor
    }

    public var resolvedHighlightColor: Color {
        highlightColor == .custom ? Color(customHighlightColor) : highlightColor.swiftUIColor
    }

    @Published public var statusMessage: String = "Open a PDF to get started."

    // MARK: - Appearance theme

    @Published public var appTheme: AppTheme = .system {
        didSet { saveTheme() }
    }

    /// Thumbnail (Pages tab) zoom factor. 1.0 = 72x96pt, clamped 0.5...5.0.
    @Published public var thumbnailScale: CGFloat = 1.0 {
        didSet {
            let clamped = min(5.0, max(0.5, thumbnailScale))
            if clamped != thumbnailScale {
                // Terminates: re-entry sees clamped == value, so no second
                // assignment fires the observer again.
                thumbnailScale = clamped
            }
            saveTheme()
        }
    }

    /// Whether pages should render dark (color-inverted).
    public var usesDarkPages: Bool { appTheme.invertsPages }

    /// Legacy alias — use `appTheme` instead. Kept so old call sites compile.
    @available(*, deprecated, message: "Use appTheme instead")
    public var nightMode: Bool {
        get { appTheme.invertsPages }
        set { appTheme = newValue ? .dark : .light }
    }

    /// Weak link to the live PDFView so state mutations can drive navigation.
    /// Set by `PDFKitView.Coordinator` on creation.
    public weak var pdfView: PDFView?

    /// Page the PDF view should be driven to on its next SwiftUI update
    /// pass. Consumed (and cleared) by `PDFKitView.updateNSView`, which is
    /// where the document is actually committed to the PDFView — so tab
    /// switches and restores land on the saved page instead of page 0.
    public var pendingNavigationPageIndex: Int?

    /// Exact visible location (page + point within the page) for a pending
    /// navigation, preferred over `pendingNavigationPageIndex`. Set when a
    /// captured tab location is available so switching back to a tab lands
    /// on the same section of the page, not just the page top.
    var pendingNavigationDestination: (pageIndex: Int, point: CGPoint)?

    /// Per-file visible section captured when leaving its tab (keyed by
    /// file path). Session-lifetime; one-shot on restore. Keyed by path so
    /// tab removal/reordering can't orphan entries.
    private var savedTabLocations: [String: (pageIndex: Int, point: CGPoint)] = [:]

    /// Bound for `applyPendingNavigation` retries: initial PDFView layout
    /// passes can reset the scroll position after a `go(to:)`, so the
    /// navigation is re-issued until the view reports the target page — or
    /// until this deadline expires (unreachable target, user navigating).
    var pendingNavigationDeadline: Date?

    /// Applies the pending page to `view` and clears it. No-ops when the
    /// document is missing or out of sync with `view`.
    public func consumePendingNavigation(in view: PDFView) {
        guard document != nil, view.document === document else { return }
        applyPendingNavigation(in: view)
    }

    /// Executes the pending navigation (exact section first, page top
    /// otherwise). One `go(to:)` fired around the document commit is not
    /// enough: PDFView's initial layout pass can reset the scroll position
    /// afterwards, silently landing the user back on the top page — so the
    /// navigation is re-issued one runloop turn apart until the view
    /// reports showing the target page, or the 2 s deadline expires.
    private func applyPendingNavigation(in view: PDFView) {
        guard let doc = document, doc === view.document else { return }
        if let deadline = pendingNavigationDeadline, Date() >= deadline {
            pendingNavigationDestination = nil
            pendingNavigationPageIndex = nil
            pendingNavigationDeadline = nil
            return
        }
        if pendingNavigationDestination == nil, pendingNavigationPageIndex == nil {
            pendingNavigationDeadline = nil
            return
        }
        if pendingNavigationDeadline == nil {
            pendingNavigationDeadline = Date().addingTimeInterval(2)
        }
        let targetPage: Int
        let targetPoint: CGPoint?
        if let dest = pendingNavigationDestination {
            targetPage = dest.pageIndex
            targetPoint = dest.point
        } else if let idx = pendingNavigationPageIndex {
            targetPage = idx
            targetPoint = nil
        } else {
            return
        }
        guard targetPage < doc.pageCount, let page = doc.page(at: targetPage) else {
            pendingNavigationDestination = nil
            pendingNavigationPageIndex = nil
            pendingNavigationDeadline = nil
            return
        }
        DispatchQueue.main.async { [weak self, weak view] in
            guard let view, let self, self.document === doc, view.document === doc else { return }
            if let point = targetPoint {
                view.go(to: PDFDestination(page: page, at: point))
            } else {
                view.go(to: page)
            }
            let current = view.currentPage.flatMap { doc.index(for: $0) }
            if current == targetPage {
                self.pendingNavigationDestination = nil
                self.pendingNavigationPageIndex = nil
                self.pendingNavigationDeadline = nil
            } else {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.applyPendingNavigation(in: view)
                }
            }
        }
    }

    /// Undoable annotation change. PDFKit has no undo support, so the state
    /// records inverse operations itself.
    private enum AnnotationChange {
        /// Annotations we added (undo removes them, redo re-adds them).
        case added(pairs: [(page: PDFPage, annotation: PDFAnnotation)])
        /// An annotation we removed (undo re-adds it, redo removes it).
        case removed(page: PDFPage, annotation: PDFAnnotation)
    }

    private var undoStack: [AnnotationChange] = []
    private var redoStack: [AnnotationChange] = []

    public var canUndo: Bool { document != nil && !undoStack.isEmpty }
    public var canRedo: Bool { document != nil && !redoStack.isEmpty }

    /// Adds or removes a color from the rotation shortlist (never empties it).
    public func toggleFavorite(_ color: HighlightColor) {
        if let idx = favoriteColors.firstIndex(of: color) {
            guard favoriteColors.count > 1 else { return }
            favoriteColors.remove(at: idx)
        } else {
            favoriteColors.append(color)
        }
    }

    /// Advances to the next color in the rotation shortlist (wraps around).
    public func cycleHighlightColor(silent: Bool = false) {
        guard !favoriteColors.isEmpty else {
            if !silent {
                statusMessage = "Add colors to the rotation from the color menu."
            }
            return
        }
        if let idx = favoriteColors.firstIndex(of: highlightColor) {
            highlightColor = favoriteColors[(idx + 1) % favoriteColors.count]
        } else {
            highlightColor = favoriteColors[0]
        }
        if !silent, let pos = favoriteColors.firstIndex(of: highlightColor) {
            statusMessage = "Highlight color: \(highlightColor.displayName) (\(pos + 1) of \(favoriteColors.count))."
        }
    }

    private static let highlightColorKey = "com.pdfreader.highlightColor.v1"
    private static let customColorKey = "com.pdfreader.highlightCustomColor.v1"
    private static let favoritesKey = "com.pdfreader.highlightFavorites.v1"
    private static let themeKey = "com.pdfreader.appTheme.v1"
    private static let thumbnailScaleKey = "com.pdfreader.thumbnailScale.v1"
    private static let remembersPositionKey = "com.pdfreader.remembersLastPosition.v1"
    private static let lastPositionsKey = "com.pdfreader.lastPositions.v1"
    private static let openTabsKey = "com.pdfreader.openTabs.v1"
    private static let activeTabKey = "com.pdfreader.activeTab.v1"
    /// While restoring the session, tab mutations must not write back
    /// (mirrors the `loadingPrefs` guard for highlight/theme prefs).
    private var restoringSession = false
    /// While loading, assignments must not save back mid-load (the choice
    /// restores before the custom value, which would clobber it).
    private var loadingPrefs = false

    public init() {
        loadHighlightPrefs()
        loadThemePrefs()
    }

    private func saveHighlightPrefs() {
        guard !loadingPrefs else { return }
        UserDefaults.standard.set(highlightColor.rawValue, forKey: Self.highlightColorKey)
        UserDefaults.standard.set(favoriteColors.map(\.rawValue), forKey: Self.favoritesKey)
        if let srgb = customHighlightColor.usingColorSpace(.sRGB) {
            UserDefaults.standard.set(
                "\(srgb.redComponent) \(srgb.greenComponent) \(srgb.blueComponent)",
                forKey: Self.customColorKey
            )
        }
    }

    private func loadHighlightPrefs() {
        loadingPrefs = true
        defer { loadingPrefs = false }
        if let raw = UserDefaults.standard.string(forKey: Self.highlightColorKey),
           let saved = HighlightColor(rawValue: raw)
        {
            highlightColor = saved
        }
        if let str = UserDefaults.standard.string(forKey: Self.customColorKey) {
            let parts = str.split(separator: " ").compactMap { Double(String($0)) }
            if parts.count == 3 {
                customHighlightColor = NSColor(
                    srgbRed: CGFloat(parts[0]),
                    green: CGFloat(parts[1]),
                    blue: CGFloat(parts[2]),
                    alpha: 1.0
                )
            }
        }
        if let raws = UserDefaults.standard.stringArray(forKey: Self.favoritesKey), !raws.isEmpty {
            let list = raws.compactMap { HighlightColor(rawValue: $0) }
            if !list.isEmpty {
                favoriteColors = list
            }
        }
    }

    private var loadingTheme = false

    private func saveTheme() {
        guard !loadingTheme else { return }
        UserDefaults.standard.set(appTheme.rawValue, forKey: Self.themeKey)
        UserDefaults.standard.set(Double(thumbnailScale), forKey: Self.thumbnailScaleKey)
    }

    private func loadThemePrefs() {
        loadingTheme = true
        defer { loadingTheme = false }
        if let raw = UserDefaults.standard.string(forKey: Self.themeKey),
           let saved = AppTheme(rawValue: raw)
        {
            appTheme = saved
        }
        let scale = UserDefaults.standard.double(forKey: Self.thumbnailScaleKey)
        if scale >= 0.5, scale <= 5.0, scale != 0 {
            thumbnailScale = CGFloat(scale)
        }
        // One-time migration: an enabled legacy night mode becomes Dark.
        if UserDefaults.standard.bool(forKey: "com.pdfreader.nightMode.v1"), appTheme == .system {
            appTheme = .dark
        }
    }

    /// Zoom helpers for the Pages (thumbnails) tab.
    public func zoomThumbnailsIn() {
        thumbnailScale = min(5.0, thumbnailScale + 0.25)
    }

    public func zoomThumbnailsOut() {
        thumbnailScale = max(0.5, thumbnailScale - 0.25)
    }

    public func resetThumbnailZoom() {
        thumbnailScale = 1.0
    }

    // MARK: - Opening

    @discardableResult
    public func open(url: URL) -> Bool {
        // Re-opening an already-open file activates its existing tab.
        if let idx = tabURLs.firstIndex(of: url) {
            // Already showing this exact file? Nothing to reload — a reload
            // would replace the document and reset the scroll position.
            if idx == activeTabIndex, url == fileURL, document != nil { return true }
            activeTabIndex = idx
        } else {
            tabURLs.append(url)
            activeTabIndex = tabURLs.count - 1
        }
        return loadDocument(at: url)
    }

    /// Switches the active tab and loads its document.
    @discardableResult
    public func switchToTab(_ index: Int) -> Bool {
        guard tabURLs.indices.contains(index) else { return false }
        // Clicking the active tab: nothing to do — a reload would replace
        // the document and reset the scroll position.
        if index == activeTabIndex, tabURLs[index] == fileURL, document != nil { return true }
        activeTabIndex = index
        return loadDocument(at: tabURLs[index])
    }

    /// Closes the tab at `index`, activating a neighbor, or clears the
    /// view when the last tab closes.
    public func closeTab(at index: Int) {
        guard tabURLs.indices.contains(index) else { return }
        tabURLs.remove(at: index)
        if tabURLs.isEmpty {
            activeTabIndex = 0
            document = nil
            fileURL = nil
            pageCount = 0
            outlineNodes = []
            annotationRows = []
            searchHits = []
            searchQuery = ""
            pdfView?.highlightedSelections = nil
            pdfView?.currentSelection = nil
            statusMessage = "Open a PDF to get started."
            return
        }
        let next = min(index, tabURLs.count - 1)
        activeTabIndex = next
        loadDocument(at: tabURLs[next])
    }

    /// Loads `url` into the viewer. The URL must already be tracked in
    /// `tabURLs` by the caller (`open`/`switchToTab`).
    private func loadDocument(at url: URL) -> Bool {
        // Leaving the current tab: capture its exact visible section
        // (page + point) so switching back returns there instead of the
        // page top. Must run before `fileURL` is reassigned below.
        if let view = pdfView,
           let current = document,
           let previousURL = fileURL,
           previousURL != url,
           view.document === current,
           let dest = view.currentDestination,
           let destPage = dest.page
        {
            let capturing = (pageIndex: current.index(for: destPage), point: dest.point)
            savedTabLocations[previousURL.path] = capturing
        }
        guard let doc = PDFDocument(url: url) else {
            statusMessage = "Could not open \(url.lastPathComponent)."
            return false
        }

        document = doc
        fileURL = url
        pageCount = doc.pageCount
        searchHits = []
        searchQuery = ""
        pdfView?.highlightedSelections = nil
        pdfView?.currentSelection = nil
        rebuildOutline()
        refreshAnnotations()
        undoStack.removeAll()
        redoStack.removeAll()
        let saved = restoreLastPositionIndex() ?? 0
        currentPageIndex = saved
        // Drive the view to the saved location on the next updateNSView pass —
        // right now `pdfView` still shows the previous document, so a direct
        // `go(to:)` here would be aimed at the wrong PDF (the view commits
        // the new document on a later SwiftUI tick). Prefer an exact captured
        // section for tab switches; fall back to the page top.
        if let loc = savedTabLocations.removeValue(forKey: url.path) {
            pendingNavigationDestination = loc
            pendingNavigationPageIndex = nil
        } else {
            pendingNavigationPageIndex = saved
        }
        statusMessage = "\(url.lastPathComponent) — \(doc.pageCount) pages"
        return true
    }

    // MARK: - Last reading position

    /// Whether per-file last page is remembered. Defaults to on.
    public var remembersLastPosition: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.remembersPositionKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.remembersPositionKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.remembersPositionKey) }
    }

    private func saveLastPosition() {
        guard remembersLastPosition, document != nil, let url = fileURL else { return }
        var all = UserDefaults.standard.dictionary(forKey: Self.lastPositionsKey) as? [String: Int] ?? [:]
        all[url.path] = currentPageIndex
        UserDefaults.standard.set(all, forKey: Self.lastPositionsKey)
    }

    private func restoreLastPositionIndex() -> Int? {
        guard remembersLastPosition, let url = fileURL else { return nil }
        let all = UserDefaults.standard.dictionary(forKey: Self.lastPositionsKey) as? [String: Int] ?? [:]
        guard let idx = all[url.path] else { return nil }
        return max(0, min(idx, max(0, pageCount - 1)))
    }

    // MARK: - Session restore

    /// Persists the open tabs and active tab so quitting and relaunching
    /// brings back the same documents (per-file last page is saved by
    /// `saveLastPosition()` on every page change).
    private func saveSession() {
        guard !restoringSession else { return }
        UserDefaults.standard.set(tabURLs.map(\.path), forKey: Self.openTabsKey)
        UserDefaults.standard.set(activeTabIndex, forKey: Self.activeTabKey)
    }

    /// Reopens the tabs from the previous session. Files that no longer
    /// exist are skipped; if nothing loads, the app starts clean. Called
    /// from `ContentView.onAppear` once the PDF view exists (also keeps
    /// library tests, which build a bare state, unaffected).
    public func restoreSession() {
        guard document == nil, tabURLs.isEmpty else { return }
        let saved = UserDefaults.standard.stringArray(forKey: Self.openTabsKey) ?? []
        let urls = saved
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }

        restoringSession = true
        tabURLs = urls
        let savedIndex = UserDefaults.standard.integer(forKey: Self.activeTabKey)
        activeTabIndex = min(max(0, savedIndex), urls.count - 1)
        restoringSession = false

        // Prefer the active tab; if it fails to parse, try the others.
        var loaded = false
        for idx in [activeTabIndex] + tabURLs.indices.filter({ $0 != activeTabIndex }) {
            activeTabIndex = idx
            if loadDocument(at: tabURLs[idx]) {
                loaded = true
                break
            }
        }
        if !loaded {
            tabURLs = []
            activeTabIndex = 0
            statusMessage = "Open a PDF to get started."
        }
        saveSession()
    }

    // MARK: - Navigation

    public func goToPage(index: Int, viaView: Bool = true) {
        guard let doc = document, pageCount > 0 else { return }
        let clamped = max(0, min(index, pageCount - 1))
        currentPageIndex = clamped
        saveLastPosition()
        // Navigation goes through the pending target so the PDFView moves
        // on the next updateNSView pass — see consumePendingNavigation.
        if viaView {
            pendingNavigationPageIndex = clamped
        }
    }

    public func goToNextPage() {
        goToPage(index: currentPageIndex + 1)
    }

    public func goToPreviousPage() {
        goToPage(index: currentPageIndex - 1)
    }

    public func syncCurrentPageFromView(_ view: PDFView) {
        guard let doc = document,
              let page = view.currentPage,
              let index = Optional(doc.index(for: page))
        else { return }
        if index != currentPageIndex {
            currentPageIndex = index
            saveLastPosition()
        }
        if view.scaleFactor != scaleFactor {
            scaleFactor = view.scaleFactor
        }
    }

    // MARK: - Zoom / layout

    public func zoomIn() {
        autoScales = false
        pdfView?.autoScales = false
        pdfView?.zoomIn(nil)
        if let s = pdfView?.scaleFactor {
            scaleFactor = s
        }
    }

    public func zoomOut() {
        autoScales = false
        pdfView?.autoScales = false
        pdfView?.zoomOut(nil)
        if let s = pdfView?.scaleFactor {
            scaleFactor = s
        }
    }

    public func toggleAutoScales() {
        autoScales.toggle()
        pdfView?.autoScales = autoScales
    }

    public func applyLayoutToView(_ view: PDFView) {
        view.displayMode = layout.pdfDisplayMode
        view.displaysAsBook = displaysAsBook
        view.displaysRTL = displaysRTL
        view.autoScales = autoScales
    }

    // MARK: - Outline

    public func rebuildOutline() {
        guard let doc = document, let root = doc.outlineRoot else {
            outlineNodes = []
            return
        }
        var nodes: [PDFOutlineNode] = []
        for i in 0 ..< root.numberOfChildren {
            if let child = root.child(at: i) {
                collectOutline(child, level: 0, into: &nodes)
            }
        }
        outlineNodes = nodes
    }

    private func collectOutline(_ outline: PDFOutline, level: Int, into nodes: inout [PDFOutlineNode]) {
        nodes.append(PDFOutlineNode(outline: outline, level: level))
        for i in 0 ..< outline.numberOfChildren {
            if let child = outline.child(at: i) {
                collectOutline(child, level: level + 1, into: &nodes)
            }
        }
    }

    public func goToOutline(_ node: PDFOutlineNode) {
        guard let doc = document else { return }
        if let dest = node.outline.destination, let page = dest.page {
            // viaView: false — the exact destination jump below replaces
            // the coarse page-top navigation.
            goToPage(index: doc.index(for: page), viaView: false)
            if let view = pdfView {
                view.go(to: dest)
            }
        } else if let action = node.outline.action as? PDFActionGoTo {
            let dest = action.destination
            if let page = dest.page {
                goToPage(index: doc.index(for: page), viaView: false)
                pdfView?.go(to: dest)
            }
        } else if let pageIndex = node.destinationPageIndex {
            goToPage(index: pageIndex)
        }
    }

    // MARK: - Search

    public func runSearch() {
        guard let doc = document else { return }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchHits = []
            return
        }
        isSearching = true
        // PDFKit find is synchronous; keep result list bounded for large docs.
        let selections = doc.findString(query, withOptions: [.caseInsensitive])
        var hits: [PDFSearchHit] = []
        hits.reserveCapacity(min(selections.count, 500))
        for selection in selections.prefix(500) {
            if let page = selection.pages.first {
                hits.append(PDFSearchHit(selection: selection, pageIndex: doc.index(for: page)))
            }
        }
        searchHits = hits
        currentHitIndex = 0
        isSearching = false
        if hits.isEmpty {
            statusMessage = "No matches for \"\(query)\"."
        } else {
            statusMessage = "\(hits.count) match\(hits.count == 1 ? "" : "es") for \"\(query)\"."
            focusCurrentHit()
        }
    }

    public func clearSearch() {
        searchQuery = ""
        searchHits = []
        currentHitIndex = 0
        pdfView?.highlightedSelections = nil
        if let view = pdfView {
            view.currentSelection = nil
        }
    }

    public func focusCurrentHit() {
        guard !searchHits.isEmpty else { return }
        let clamped = max(0, min(currentHitIndex, searchHits.count - 1))
        currentHitIndex = clamped
        let hit = searchHits[clamped]
        withoutAutoAnnotate {
            pdfView?.highlightedSelections = searchHits.map { $0.selection }
            pdfView?.currentSelection = hit.selection
        }
        hit.selection.pages.first.map { pdfView?.go(to: $0) }
        if let page = hit.selection.pages.first, let doc = document {
            currentPageIndex = doc.index(for: page)
        }
    }

    public func nextHit() {
        guard !searchHits.isEmpty else { return }
        currentHitIndex = (currentHitIndex + 1) % searchHits.count
        focusCurrentHit()
    }

    public func previousHit() {
        guard !searchHits.isEmpty else { return }
        currentHitIndex = (currentHitIndex - 1 + searchHits.count) % searchHits.count
        focusCurrentHit()
    }

    // MARK: - Annotations

    public func refreshAnnotations() {
        guard let doc = document else {
            annotationRows = []
            return
        }
        var rows: [PDFAnnotationRow] = []
        for i in 0 ..< doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            for annotation in page.annotations {
                rows.append(PDFAnnotationRow(annotation: annotation, pageIndex: i))
            }
        }
        annotationRows = rows
    }

    /// Markup modes that apply automatically once a text selection settles.
    /// Note mode stays manual (it needs composed content).
    public var autoAnnotateOnSelection: Bool {
        annotationMode == .highlight || annotationMode == .underline || annotationMode == .strikeThrough
    }

    /// Set while making programmatic selection changes (e.g. focusing a
    /// search hit) so those don't auto-annotate. PDFView posts synchronously
    /// on set, so a scoped flag is sufficient.
    private var suppressAutoAnnotate = false
    /// Bumps to invalidate any pending debounced auto-annotate.
    private var autoAnnotateGeneration = 0

    private func withoutAutoAnnotate(_ body: () -> Void) {
        suppressAutoAnnotate = true
        defer { suppressAutoAnnotate = false }
        body()
    }

    /// Called on `PDFViewSelectionChanged` (wired in `PDFKitView`).
    /// Debounced: mid-drag the selection changes continuously, so this waits
    /// for the selection to settle instead of annotating every fragment.
    public func handleSelectionChange() {
        autoAnnotateGeneration += 1
        guard !suppressAutoAnnotate, autoAnnotateOnSelection,
              let selection = pdfView?.currentSelection,
              selection.stringFarFromEmpty
        else { return }
        let generation = autoAnnotateGeneration
        let settledText = selection.string
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, generation == self.autoAnnotateGeneration else { return }
            guard self.autoAnnotateOnSelection,
                  let current = self.pdfView?.currentSelection,
                  current.stringFarFromEmpty,
                  current.string == settledText
            else { return }
            self.annotateCurrentSelection()
        }
    }

    /// Applies the active markup tool to the existing selection, if any.
    /// Used when picking a tool (or color) with text already selected.
    public func applyToCurrentSelectionIfPresent() {
        autoAnnotateGeneration += 1
        guard autoAnnotateOnSelection,
              let selection = pdfView?.currentSelection,
              selection.stringFarFromEmpty
        else { return }
        annotateCurrentSelection()
    }

    /// Applies the active markup tool to the PDFView's current selection,
    /// then advances to the next rotation color. Always clears the selection
    /// afterwards — this also keeps the color-change handler from re-applying.
    public func annotateCurrentSelection() {
        autoAnnotateGeneration += 1
        guard let view = pdfView,
              let selection = view.currentSelection,
              selection.stringFarFromEmpty
        else {
            statusMessage = "Select some text first, then pick Highlight / Underline / Strikethrough."
            return
        }
        let color = resolvedHighlightNSColor
        let appliedName = highlightColor.displayName
        // Use per-line selections so markup boxes hug the text instead of
        // spanning one big rectangle across wrapped lines.
        let lineSelections = selection.selectionsByLine()
        let workItems: [PDFSelection] = lineSelections.isEmpty ? [selection] : lineSelections
        var addedPairs: [(page: PDFPage, annotation: PDFAnnotation)] = []
        for item in workItems {
            for page in item.pages {
                let bounds = item.bounds(for: page)
                guard !bounds.isNull, !bounds.isEmpty else { continue }
                let markup = PDFAnnotation(
                    bounds: bounds,
                    forType: pdfAnnotationSubtype,
                    withProperties: nil
                )
                markup.color = color
                if annotationMode == .note {
                    markup.contents = "Note on page \(document?.index(for: page) ?? 0 + 1)"
                }
                page.addAnnotation(markup)
                addedPairs.append((page, markup))
            }
        }
        if !addedPairs.isEmpty {
            undoStack.append(.added(pairs: addedPairs))
            redoStack.removeAll()
        }
        view.currentSelection = nil
        refreshAnnotations()
        if !addedPairs.isEmpty, favoriteColors.count > 1 {
            cycleHighlightColor(silent: true)
            statusMessage = "\(annotationMode.displayName) applied with \(appliedName). Next up: \(highlightColor.displayName)."
        } else {
            statusMessage = "\(annotationMode.displayName) applied with \(appliedName)."
        }
    }

    private var pdfAnnotationSubtype: PDFAnnotationSubtype {
        switch annotationMode {
        case .select: return .highlight
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikeThrough: return .strikeOut
        case .note: return .text
        }
    }

    public func addNoteToCurrentPage(_ text: String) {
        guard let doc = document,
              let page = doc.page(at: currentPageIndex)
        else { return }
        let bounds = NSRect(x: 100, y: 100, width: 24, height: 24)
        let note = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        note.contents = text.isEmpty ? "New note" : text
        note.color = resolvedHighlightNSColor
        page.addAnnotation(note)
        undoStack.append(.added(pairs: [(page, note)]))
        redoStack.removeAll()
        refreshAnnotations()
    }

    public func removeAnnotation(_ row: PDFAnnotationRow) {
        guard let doc = document,
              let page = doc.page(at: row.pageIndex)
        else { return }
        page.removeAnnotation(row.annotation)
        undoStack.append(.removed(page: page, annotation: row.annotation))
        redoStack.removeAll()
        refreshAnnotations()
    }

    public func undo() {
        guard let change = undoStack.popLast() else { return }
        applyInverse(change)
        redoStack.append(change)
        refreshAnnotations()
        statusMessage = "Undid last annotation change."
    }

    public func redo() {
        guard let change = redoStack.popLast() else { return }
        applyForward(change)
        undoStack.append(change)
        refreshAnnotations()
        statusMessage = "Redid annotation change."
    }

    private func applyInverse(_ change: AnnotationChange) {
        switch change {
        case .added(let pairs):
            for (page, annotation) in pairs {
                page.removeAnnotation(annotation)
            }
        case .removed(let page, let annotation):
            page.addAnnotation(annotation)
        }
    }

    private func applyForward(_ change: AnnotationChange) {
        switch change {
        case .added(let pairs):
            for (page, annotation) in pairs {
                page.addAnnotation(annotation)
            }
        case .removed(let page, let annotation):
            page.removeAnnotation(annotation)
        }
    }

    public func goToAnnotation(_ row: PDFAnnotationRow) {
        goToPage(index: row.pageIndex, viaView: false)
        if let doc = document, let page = doc.page(at: row.pageIndex) {
            pdfView?.go(to: page.bounds(for: .mediaBox), on: page)
        }
    }

    // MARK: - Saving

    /// Writes annotations back into the opened file.
    @discardableResult
    public func save() -> Bool {
        guard let doc = document, let url = fileURL else {
            statusMessage = "Nothing to save."
            return false
        }
        let ok = doc.write(to: url)
        statusMessage = ok ? "Saved \(url.lastPathComponent)." : "Save failed — is the file writable?"
        return ok
    }

    public func saveCopy(to url: URL) -> Bool {
        guard let doc = document else { return false }
        let ok = doc.write(to: url)
        statusMessage = ok ? "Saved annotated copy to \(url.lastPathComponent)." : "Save failed."
        return ok
    }
}

private extension PDFSelection {
    /// PDFKit returns selections whose `string` may be whitespace-only.
    var stringFarFromEmpty: Bool {
        guard let s = string?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !s.isEmpty
    }
}
