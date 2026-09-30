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
}

public struct SidebarView: View {
    @ObservedObject var state: PDFReaderState
    @ObservedObject var bookmarks: BookmarkStore
    @Binding var tab: SidebarTab

    public init(state: PDFReaderState, bookmarks: BookmarkStore, tab: Binding<SidebarTab>) {
        self.state = state
        self.bookmarks = bookmarks
        self._tab = tab
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $tab) {
                ForEach(SidebarTab.allCases) { t in
                    Label(t.title, systemImage: t.symbol).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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

    private var thumbnailsTab: some View {
        PDFThumbnailStrip(state: state)
            .padding(4)
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
