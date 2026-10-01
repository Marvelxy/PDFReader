import PDFReaderKit
import SwiftUI

public enum SidebarTab: String, CaseIterable, Identifiable {
    case thumbnails
    case outline
    case search
    case bookmarks
    case annotations

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .thumbnails: return "Pages"
        case .outline: return "Contents"
        case .search: return "Search"
        case .bookmarks: return "Bookmarks"
        case .annotations: return "Notes"
        }
    }

    public var symbol: String {
        switch self {
        case .thumbnails: return "square.grid.2x2"
        case .outline: return "list.bullet"
        case .search: return "magnifyingglass"
        case .bookmarks: return "bookmark"
        case .annotations: return "note.text"
        }
    }

    public var tooltip: String {
        switch self {
        case .thumbnails: return "Pages — thumbnails (zoomable)"
        case .outline: return "Contents — table of contents"
        case .search: return "Search in document"
        case .bookmarks: return "Bookmarks for this file"
        case .annotations: return "Notes — annotations list"
        }
    }
}

public struct SidebarView: View {
    @ObservedObject var state: PDFReaderState
    @ObservedObject var bookmarks: BookmarkStore
    @Binding var tab: SidebarTab
    /// Draft slider value while the thumbnail zoom slider is being dragged.
    /// While non-nil the expensive `state.thumbnailScale` commit (which forces
    /// `PDFThumbnailView` to re-render every thumbnail) is deferred until
    /// drag end — dragging otherwise floods the main thread with full
    /// thumbnail reloads and freezes the app with no recovery on large docs.
    @State private var thumbZoomDraft: Double?

    public init(state: PDFReaderState, bookmarks: BookmarkStore, tab: Binding<SidebarTab>) {
        self.state = state
        self.bookmarks = bookmarks
        self._tab = tab
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Icon-only tab bar with tooltips (accessibility labels = titles).
            HStack(spacing: 2) {
                ForEach(SidebarTab.allCases) { t in
                    Button {
                        tab = t
                    } label: {
                        Image(systemName: t.symbol)
                            .font(.system(size: 14, weight: tab == t ? .semibold : .regular))
                            .foregroundStyle(tab == t ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(
                                tab == t ? Color.accentColor.opacity(0.15) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(t.tooltip)
                    .accessibilityLabel(t.title)
                }
            }
            .padding(8)

            Divider()

            switch tab {
            case .thumbnails:
                thumbnailsTab
            case .outline:
                outlineTab
            case .search:
                searchTab
            case .bookmarks:
                bookmarksTab
            case .annotations:
                annotationsTab
            }
        }
    }

    // MARK: - Tabs

    /// Scale shown in the zoom bar: live draft while dragging, else committed.
    private var thumbDisplayScale: CGFloat {
        if let draft = thumbZoomDraft {
            return CGFloat(draft)
        }
        return state.thumbnailScale
    }

    private var thumbSliderBinding: Binding<Double> {
        Binding(
            get: {
                if let draft = thumbZoomDraft { return draft }
                return Double(state.thumbnailScale)
            },
            set: { thumbZoomDraft = $0 }
        )
    }

    private func commitThumbDraft() {
        if let draft = thumbZoomDraft {
            thumbZoomDraft = nil
            state.thumbnailScale = CGFloat(draft)
        }
    }

    private var thumbnailZoomBar: some View {
        // The slider edits a local draft while dragging and commits to
        // `state.thumbnailScale` only on release: committing live would
        // ask PDFThumbnailView to re-render all thumbnails on every tick
        // and lock up the main thread on large documents.
        HStack(spacing: 6) {
            Button {
                thumbZoomDraft = nil
                state.zoomThumbnailsOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Zoom thumbnails out")
            .disabled(state.thumbnailScale <= 0.5)

            Slider(
                value: thumbSliderBinding,
                in: 0.5 ... 5.0,
                step: 0.25
            ) { editing in
                if !editing { commitThumbDraft() }
            }
            .help("Thumbnail zoom (\(Int(thumbDisplayScale * 100))% — double-click to reset)")
            .onTapGesture(count: 2) {
                thumbZoomDraft = nil
                state.resetThumbnailZoom()
            }

            Button {
                thumbZoomDraft = nil
                state.zoomThumbnailsIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Zoom thumbnails in")
            .disabled(state.thumbnailScale >= 5.0)

            Text("\(Int(thumbDisplayScale * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
                .help("Thumbnail zoom — double-click slider to reset to 100%")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var thumbnailsTab: some View {
        VStack(spacing: 0) {
            thumbnailZoomBar
            Divider()
            PDFThumbnailStrip(state: state)
                .padding(4)
        }
    }

    private var outlineTab: some View {
        Group {
            if state.outlineNodes.isEmpty {
                emptyHint("No table of contents in this PDF.")
            } else {
                List(state.outlineNodes) { node in
                    Button {
                        state.goToOutline(node)
                    } label: {
                        HStack {
                            Text(node.label)
                                .lineLimit(2)
                                .padding(.leading, CGFloat(node.level) * 12)
                            Spacer()
                            if let page = node.destinationPageIndex {
                                Text("\(page + 1)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var searchTab: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search in document", text: $state.searchQuery, onCommit: {
                    state.runSearch()
                })
                .textFieldStyle(.roundedBorder)
                Button {
                    state.runSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Search")
                if !state.searchHits.isEmpty {
                    Button {
                        state.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            if state.isSearching {
                ProgressView("Searching…")
                    .padding()
            } else if !state.searchHits.isEmpty {
                HStack {
                    Text("\(state.currentHitIndex + 1) of \(state.searchHits.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        state.previousHit()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(state.searchHits.isEmpty)
                    Button {
                        state.nextHit()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(state.searchHits.isEmpty)
                }
                .padding(.horizontal, 8)

                List {
                    ForEach(Array(state.searchHits.enumerated()), id: \.element.id) { index, hit in
                        Button {
                            state.currentHitIndex = index
                            state.focusCurrentHit()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Page \(hit.pageIndex + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(hit.preview)
                                    .lineLimit(3)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(index == state.currentHitIndex ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                }
                .listStyle(.sidebar)
            } else {
                emptyHint("Type a phrase and press Return.")
            }
            Spacer()
        }
    }

    private var bookmarksTab: some View {
        Group {
            let items = bookmarks.bookmarks(for: state.fileName)
            if items.isEmpty {
                emptyHint("No bookmarks for this file yet.\nUse ☆ in the toolbar.")
            } else {
                List {
                    ForEach(items) { mark in
                        HStack {
                            Button {
                                state.goToPage(index: mark.pageIndex)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(mark.label)
                                    Text(mark.createdAt, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button {
                                bookmarks.remove(id: mark.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .help("Remove bookmark")
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var annotationsTab: some View {
        Group {
            if state.annotationRows.isEmpty {
                emptyHint("No annotations yet.\nSelect text, pick a color, then Highlight.")
            } else {
                List {
                    ForEach(state.annotationRows) { row in
                        HStack(alignment: .top) {
                            Button {
                                state.goToAnnotation(row)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(row.typeLabel.capitalized) — Page \(row.pageIndex + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !row.contents.isEmpty {
                                        Text(row.contents).lineLimit(3)
                                    } else {
                                        Text("(no note text)").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button {
                                state.removeAnnotation(row)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .help("Delete annotation")
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding()
            Spacer()
        }
    }
}
