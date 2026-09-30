import AppKit
import PDFReaderKit
import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @StateObject private var state = PDFReaderState()
    @StateObject private var bookmarks = BookmarkStore()
    @StateObject private var recents = RecentFilesStore()
    @State private var sidebarTab: SidebarTab = .outline
    @State private var showingSidebar = true
    @State private var sidebarWidth: CGFloat = 280
    @State private var hoveringDivider = false
    @State private var dividerDragAnchor: CGFloat?
    @State private var noteText = ""
    @State private var showingNoteComposer = false

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            if showingSidebar {
                SidebarView(state: state, bookmarks: bookmarks, tab: $sidebarTab)
                    .frame(width: sidebarWidth)
                sidebarDivider
            }
            VStack(spacing: 0) {
                if state.document == nil {
                    welcomeView
                } else {
                    PDFKitView(state: state)
                        .colorInvertIfActive(state.nightMode)
                        .background(state.nightMode ? Color.black : Color(nsColor: .windowBackgroundColor))
                }
                statusBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Menu {
                        Button("Open…") {
                            openDocument()
                        }
                        .keyboardShortcut("o", modifiers: .command)
                        if !recents.items.isEmpty {
                            Section("Open Recent") {
                                ForEach(recents.items) { item in
                                    Button(item.name) {
                                        openRecent(item)
                                    }
                                }
                                Divider()
                                Button("Clear Menu") {
                                    recents.clear()
                                }
                            }
                        }
                    } label: {
                        Label("Open", systemImage: "folder")
                    }
                    .help("Open PDF (⌘O)")

                    Button {
                        showingSidebar.toggle()
                    } label: {
                        Label("Sidebar", systemImage: "sidebar.leading")
                    }
                    .help("Toggle sidebar")
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    pageNavigation
                }

                ToolbarItemGroup {
                    zoomControls
                }

                ToolbarItemGroup {
                    layoutMenu
                }

                ToolbarItemGroup {
                    annotationTools
                }

                ToolbarItemGroup {
                    Button {
                        state.undo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .help("Undo last annotation change (⌘Z)")
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!state.canUndo)

                    Button {
                        state.redo()
                    } label: {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .help("Redo annotation change (⇧⌘Z)")
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!state.canRedo)
                }

                ToolbarItemGroup {
                    Button {
                        toggleBookmark()
                    } label: {
                        Label(
                            "Bookmark",
                            systemImage: bookmarks.isBookmarked(
                                fileName: state.fileName,
                                pageIndex: state.currentPageIndex
                            ) ? "star.fill" : "star"
                        )
                    }
                    .help("Bookmark this page")
                    .disabled(state.document == nil)

                    Button {
                        state.nightMode.toggle()
                    } label: {
                        Label("Night", systemImage: state.nightMode ? "moon.fill" : "moon")
                    }
                    .help("Toggle night mode (dark pages)")

                    Button {
                        toggleFullScreen()
                    } label: {
                        Label("Present", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Presentation / full screen")

                    Button {
                        saveInPlace()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .help("Save annotations to this file (⌘S)")
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(state.document == nil)

                    Button {
                        saveCopy()
                    } label: {
                        Label("Save Copy", systemImage: "square.and.arrow.down.on.square")
                    }
                    .help("Save annotated copy to a new file…")
                    .disabled(state.document == nil)
                }
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        // Picking a markup tool (or color) with text already selected
        // applies it immediately — no separate Apply tap needed.
        .onChange(of: state.annotationMode) { _, _ in
            state.applyToCurrentSelectionIfPresent()
        }
        .onChange(of: state.highlightColor) { _, _ in
            state.applyToCurrentSelectionIfPresent()
        }
        .preferredColorScheme(state.nightMode ? .dark : nil)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            // Handy for `swift run` smoke tests: `PDFREADER_SAMPLE=/path/to.pdf swift run`
            if let sample = ProcessInfo.processInfo.environment["PDFREADER_SAMPLE"] {
                let url = URL(fileURLWithPath: sample)
                open(url: url)
            }
        }
        .sheet(isPresented: $showingNoteComposer) {
            noteComposer
        }
    }

    // MARK: - Subviews

    /// Explicit draggable divider between sidebar and detail: a neutral
    /// gray strip (11pt hit zone) with resize cursor, drag-to-resize
    /// (200–500pt), and double-click to reset. Cursor comes from the
    /// native `.columnResizePointerStyle()` plus an AppKit cursor rect.
    private var sidebarDivider: some View {
        Color(nsColor: hoveringDivider ? .gridColor : .separatorColor)
            .frame(width: hoveringDivider ? 2 : 1)
            .frame(width: 11)
            .frame(maxHeight: .infinity)
            .columnResizePointerStyle()
            .overlay(
                ResizeHandleOverlay(
                    onHover: { hovering in
                        hoveringDivider = hovering
                    },
                    onDragStart: {
                        dividerDragAnchor = sidebarWidth
                    },
                    onDragChanged: { dx in
                        let base = dividerDragAnchor ?? sidebarWidth
                        sidebarWidth = min(500, max(200, base + dx))
                    },
                    onDragEnded: {
                        dividerDragAnchor = nil
                    },
                    onDoubleClick: {
                        sidebarWidth = 280
                    }
                )
            )
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.pages")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("PDFReader for Mac")
                .font(.largeTitle)
            Text("Open a PDF to read, search, highlight with switchable colors, and take notes.")
                .foregroundStyle(.secondary)
            Button("Open PDF…") {
                openDocument()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)
            if !recents.items.isEmpty {
                Divider()
                    .frame(maxWidth: 360)
                Text("Recent files")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    ForEach(recents.items.prefix(5)) { item in
                        Button {
                            openRecent(item)
                        } label: {
                            HStack {
                                Image(systemName: "doc")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.name)
                                        .lineLimit(1)
                                    Text(item.url.deletingLastPathComponent().path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(RecentFile.ageDescription(for: item.lastOpened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: 360)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text(state.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if state.pageCount > 0 {
                Text("Page \(state.currentPageIndex + 1) of \(state.pageCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(state.scaleFactor * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var pageNavigation: some View {
        Group {
            Button {
                state.goToPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous page (←)")
            .disabled(state.currentPageIndex <= 0)

            TextField(
                "Page",
                value: Binding(
                    get: { state.currentPageIndex + 1 },
                    set: { state.goToPage(index: $0 - 1) }
                ),
                formatter: NumberFormatter()
            )
            .frame(width: 48)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .help("Current page number")
            .disabled(state.document == nil)

            Text("of \(state.pageCount)")
                .foregroundStyle(.secondary)

            Button {
                state.goToNextPage()
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next page (→)")
            .disabled(state.currentPageIndex >= state.pageCount - 1)
        }
    }

    private var zoomControls: some View {
        Group {
            Button {
                state.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")
            .disabled(state.document == nil)

            Button {
                state.toggleAutoScales()
            } label: {
                Image(systemName: state.autoScales ? "arrow.up.left.and.down.right.magnifyingglass" : "checkmark.magnifyingglass")
            }
            .help(state.autoScales ? "Auto-fit is on — click for manual zoom" : "Auto-fit is off — click to fit to window")

            Button {
                state.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")
            .disabled(state.document == nil)
        }
    }

    private var layoutMenu: some View {
        Menu {
            ForEach(ReadingLayout.allCases) { layout in
                Button {
                    state.layout = layout
                    if let view = state.pdfView {
                        state.applyLayoutToView(view)
                    }
                } label: {
                    if state.layout == layout {
                        Label(layout.displayName, systemImage: "checkmark")
                    } else {
                        Text(layout.displayName)
                    }
                }
            }
            Divider()
            Toggle("Show as book (facing pages)", isOn: $state.displaysAsBook)
            Toggle("Right-to-left", isOn: $state.displaysRTL)
        } label: {
            Label("Layout", systemImage: "book")
        }
        .help("Reading layout: single, two-page, continuous")
        .disabled(state.document == nil)
        .onChange(of: state.displaysAsBook) { _, _ in
            if let view = state.pdfView { state.applyLayoutToView(view) }
        }
        .onChange(of: state.displaysRTL) { _, _ in
            if let view = state.pdfView { state.applyLayoutToView(view) }
        }
    }

    private var annotationTools: some View {
        Group {
            Picker("Tool", selection: $state.annotationMode) {
                ForEach(AnnotationMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 280)
            .disabled(state.document == nil)

            // Switchable highlight colors — applies to highlight /
            // underline / strikethrough / note tools.
            Menu {
                ForEach(HighlightColor.presets) { color in
                    Button {
                        state.highlightColor = color
                    } label: {
                        HStack {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 12, height: 12)
                            Text(color.displayName)
                            if state.favoriteColors.contains(color) {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                            if state.highlightColor == color {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                // Single Custom entry: the well shows the stored custom
                // color; picking in it stores and activates custom.
                ColorPicker(selection: customSlotBinding) {
                    HStack {
                        Circle()
                            .fill(Color(state.customHighlightColor))
                            .frame(width: 12, height: 12)
                        Text("Custom")
                        if state.favoriteColors.contains(.custom) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                        if state.highlightColor == .custom {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Divider()
                // Rotation shortlist: toggles stay switchable without
                // dismissing, and order follows selection order.
                Menu("Highlight rotation") {
                    ForEach(HighlightColor.allCases) { color in
                        Toggle(isOn: Binding(
                            get: { state.favoriteColors.contains(color) },
                            set: { _ in state.toggleFavorite(color) }
                        )) {
                            HStack {
                                Circle()
                                    .fill(color == .custom ? Color(state.customHighlightColor) : color.swiftUIColor)
                                    .frame(width: 12, height: 12)
                                Text(color.displayName)
                            }
                        }
                    }
                }
            } label: {
                // AppKit-drawn dot: a SwiftUI Circle() label does not render
                // in Tahoe toolbar menus (only the chevrons showed up), while
                // an NSImage icon is the standard supported path. The Menu
                // supplies its own chevron, so none is added here.
                Image(nsImage: Self.highlightSwatch(for: state.resolvedHighlightNSColor))
                    .accessibilityLabel("Highlight color")
            }
            .help("Highlight color — applies to markup tools")
            .disabled(state.document == nil)

            Button {
                state.cycleHighlightColor()
            } label: {
                Label("Next Color", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Next color in your rotation (⇧⌘C)")
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(state.document == nil)

            Button {
                state.annotateCurrentSelection()
            } label: {
                Label("Apply", systemImage: "highlighter")
            }
            .help("Apply active markup tool to selected text")
            .disabled(state.document == nil || state.annotationMode == .select)

            Button {
                showingNoteComposer = true
            } label: {
                Label("Note", systemImage: "note.text.badge.plus")
            }
            .help("Add sticky note to current page")
            .disabled(state.document == nil)
        }
    }

    private var noteComposer: some View {
        VStack(spacing: 12) {
            Text("New note — Page \(state.currentPageIndex + 1)")
                .font(.headline)
            TextEditor(text: $noteText)
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(0.3))
            HStack {
                // Color applies to the note icon as well.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(HighlightColor.presets) { color in
                            colorDot(for: color, resolved: color.swiftUIColor)
                        }
                        colorDot(for: .custom, resolved: Color(state.customHighlightColor))
                    }
                }
                Spacer()
                Button("Cancel") {
                    showingNoteComposer = false
                    noteText = ""
                }
                .keyboardShortcut(.cancelAction)
                Button("Add Note") {
                    state.addNoteToCurrentPage(noteText)
                    showingNoteComposer = false
                    noteText = ""
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 380, minHeight: 260)
    }

    private func colorDot(for color: HighlightColor, resolved: Color) -> some View {
        Circle()
            .fill(resolved)
            .frame(width: 22, height: 22)
            .overlay(
                Circle().stroke(
                    state.highlightColor == color ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
            )
            .onTapGesture { state.highlightColor = color }
            .help(color.displayName)
    }

    /// Drives the Custom menu row's well: shows the stored custom color,
    /// while the menu's face dot (`resolvedHighlightColor`) always shows
    /// the currently active color. Picking here stores and activates custom.
    private var customSlotBinding: Binding<Color> {
        Binding(
            get: { Color(state.customHighlightColor) },
            set: {
                state.customHighlightColor = NSColor($0)
                state.highlightColor = .custom
            }
        )
    }

    /// 16pt color dot with a subtle ring, drawn in AppKit so it renders
    /// reliably as a toolbar Menu label on all macOS versions.
    private static func highlightSwatch(for color: NSColor) -> NSImage {
        let size: CGFloat = 16
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let circle = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: size - 3, height: size - 3))
        color.setFill()
        circle.fill()
        NSColor(white: 0.55, alpha: 0.7).setStroke()
        circle.lineWidth = 1
        circle.stroke()
        img.unlockFocus()
        return img
    }

    // MARK: - Actions

    private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                open(url: url)
            }
        }
    }

    @discardableResult
    private func open(url: URL) -> Bool {
        let ok = state.open(url: url)
        if ok {
            recents.record(url)
        }
        return ok
    }

    private func openRecent(_ item: RecentFile) {
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            state.statusMessage = "\(item.name) is no longer available."
            recents.remove(item.url)
            return
        }
        open(url: item.url)
    }

    private func toggleBookmark() {
        guard state.document != nil else { return }
        bookmarks.toggle(fileName: state.fileName, pageIndex: state.currentPageIndex)
    }

    private func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private func saveInPlace() {
        _ = state.save()
    }

    private func saveCopy() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = state.fileName.replacingOccurrences(of: ".pdf", with: " annotated.pdf")
        panel.begin { response in
            if response == .OK, let url = panel.url {
                _ = state.saveCopy(to: url)
            }
        }
    }
}

// MARK: - Sidebar resize handle

/// Declarative resize cursor for the divider (macOS 15+). This is the
/// primary path: the system shows the column-resize pointer while the
/// pointer is over the view. The cursor rect further below covers older
/// macOS. (Note: cursors only render when running as a bundled `.app` —
/// see `scripts/make-app.sh`. A raw `swift run` binary shows the arrow.)
extension View {
    @ViewBuilder
    func columnResizePointerStyle() -> some View {
        if #available(macOS 15, *) {
            self.pointerStyle(.columnResize)
        } else {
            self
        }
    }
}

/// Transparent view covering the 11pt divider strip. Owns hover tracking
/// (sidebar highlight), the fallback cursor rect, drag-to-resize and
/// double-click reset in AppKit.
final class ResizeHandleNSView: NSView {
    var onHover: ((Bool) -> Void)?
    var onDragStart: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private var tracking: NSTrackingArea?
    private var dragStartX: CGFloat?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        toolTip = "Drag to resize sidebar (double-click to reset)"
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        if let t = tracking { addTrackingArea(t) }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !bounds.isEmpty {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        dragStartX = event.locationInWindow.x
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startX = dragStartX else { return }
        onDragChanged?(event.locationInWindow.x - startX)
    }

    override func mouseUp(with event: NSEvent) {
        if dragStartX != nil {
            dragStartX = nil
            onDragEnded?()
        }
    }
}

struct ResizeHandleOverlay: NSViewRepresentable {
    var onHover: (Bool) -> Void
    var onDragStart: () -> Void
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: () -> Void
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> ResizeHandleNSView {
        let view = ResizeHandleNSView()
        view.onHover = onHover
        view.onDragStart = onDragStart
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {
        nsView.onHover = onHover
        nsView.onDragStart = onDragStart
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
        nsView.onDoubleClick = onDoubleClick
    }
}

// MARK: - Night mode helper

extension View {
    /// Inverts the view only when `active` is true.
    /// Used for night mode: PDFKit has no dark page rendering, so we
    /// invert the rendered pages (white paper -> black). Applied *before*
    /// any `.background`, so the surrounding background stays dark.
    @ViewBuilder
    func colorInvertIfActive(_ active: Bool) -> some View {
        if active {
            self.colorInvert()
        } else {
            self
        }
    }
}
