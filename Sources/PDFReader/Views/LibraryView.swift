import AppKit
import Foundation
import PDFKit
import PDFReaderKit
import SwiftUI

/// How the Library shelves are laid out.
enum LibraryLayout: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }
}

/// Lazily renders first-page cover thumbnails and keeps them in memory so
/// switching between list and grid (or leaving and re-entering the
/// library) doesn't reload every PDF.
@MainActor
final class LibraryCoverCache: ObservableObject {
    static let shared = LibraryCoverCache()

    @Published private(set) var images: [String: NSImage] = [:]
    private var loading: Set<String> = []

    func image(for url: URL) -> NSImage? {
        images[url.path]
    }

    func load(url: URL) {
        let key = url.path
        guard images[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        Task {
            let image = await Task.detached(priority: .utility) {
                Self.renderCover(url: url)
            }.value
            loading.remove(key)
            if let image {
                images[key] = image
            }
        }
    }

    nonisolated private static func renderCover(url: URL) -> NSImage? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let target = CGSize(width: 240, height: 320)
        let scale = min(target.width / bounds.width, target.height / bounds.height)
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        return page.thumbnail(of: size, for: .mediaBox)
    }
}

/// Full-page library showing every tracked PDF grouped into shelves.
/// Each book shows its cover and title, reading progress, and can be moved
/// between shelves via its menu, the context menu, or drag and drop.
public struct LibraryView: View {
    @ObservedObject var state: PDFReaderState
    @ObservedObject var library: LibraryStore
    let canReturnToReading: Bool
    let onOpen: (URL) -> Void
    let onOpenDocument: () -> Void
    let onReturnToReading: () -> Void

    @ObservedObject private var coverCache = LibraryCoverCache.shared
    @AppStorage("com.pdfreader.libraryLayout.v1") private var layout: LibraryLayout = .list

    public init(
        state: PDFReaderState,
        library: LibraryStore,
        canReturnToReading: Bool,
        onOpen: @escaping (URL) -> Void,
        onOpenDocument: @escaping () -> Void,
        onReturnToReading: @escaping () -> Void
    ) {
        self.state = state
        self.library = library
        self.canReturnToReading = canReturnToReading
        self.onOpen = onOpen
        self.onOpenDocument = onOpenDocument
        self.onReturnToReading = onReturnToReading
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(LibrarySection.allCases) { section in
                        sectionView(section)
                    }
                }
                .padding(24)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background(state.appTheme.windowBackground)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.title2)
                .foregroundStyle(state.appTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Library")
                    .font(.title2.bold())
                Text("\(library.books.count) book\(library.books.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Layout", selection: $layout) {
                Image(systemName: "list.bullet")
                    .tag(LibraryLayout.list)
                Image(systemName: "square.grid.2x2")
                    .tag(LibraryLayout.grid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 84)
            .help("Switch between list and grid")
            if canReturnToReading {
                Button("Back to Reading") {
                    onReturnToReading()
                }
            }
            Button("Open PDF…") {
                onOpenDocument()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(state.appTheme.chromeBackground)
    }

    private func sectionView(_ section: LibrarySection) -> some View {
        let books = library.books(in: section)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: section.symbol)
                    .foregroundStyle(.secondary)
                Text(section.title)
                    .font(.headline)
                Text("\(books.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                Spacer()
            }
            if books.isEmpty {
                Text("No books here yet. Drag a book onto this section or use its menu to move it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if layout == .grid {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(books) { book in
                        LibraryBookCard(
                            book: book,
                            accent: state.appTheme.accent,
                            chrome: state.appTheme.chromeBackground,
                            coverCache: coverCache,
                            onOpen: { onOpen(book.url) },
                            onMove: { library.move(book.url, to: $0) },
                            onRemove: { library.remove(book.url) }
                        )
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                        LibraryBookRow(
                            book: book,
                            accent: state.appTheme.accent,
                            coverCache: coverCache,
                            onOpen: { onOpen(book.url) },
                            onMove: { library.move(book.url, to: $0) },
                            onRemove: { library.remove(book.url) }
                        )
                        if index < books.count - 1 {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .background(
                    state.appTheme.chromeBackground.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.15))
        )
        .dropDestination(for: String.self) { paths, _ in
            var moved = false
            for path in paths {
                let url = URL(fileURLWithPath: path)
                if library.books.contains(where: { $0.url.path == path && $0.section != section }) {
                    library.move(url, to: section)
                    moved = true
                }
            }
            return moved
        }
    }
}

private struct LibraryBookRow: View {
    let book: LibraryBook
    let accent: Color
    @ObservedObject var coverCache: LibraryCoverCache
    let onOpen: () -> Void
    let onMove: (LibrarySection) -> Void
    let onRemove: () -> Void

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: book.url.path)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    BookCover(url: book.url, cache: coverCache, width: 36, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.name)
                            .font(.body)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            ProgressView(value: book.clampedProgress)
                                .frame(width: 120)
                                .tint(accent)
                            Text("\(book.percentage)% read")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            if !fileExists {
                                Label("Missing", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                LibraryBookMenuItems(book: book, onMove: onMove, onRemove: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Move or remove")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .draggable(book.url.path)
        .contextMenu {
            LibraryBookMenuItems(book: book, onMove: onMove, onRemove: onRemove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.name), \(book.percentage) percent read, \(book.section.title)")
    }
}

private struct LibraryBookCard: View {
    let book: LibraryBook
    let accent: Color
    let chrome: Color
    @ObservedObject var coverCache: LibraryCoverCache
    let onOpen: () -> Void
    let onMove: (LibrarySection) -> Void
    let onRemove: () -> Void

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: book.url.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    BookCover(url: book.url, cache: coverCache, height: 170)
                    Text(book.name)
                        .font(.subheadline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                    HStack(spacing: 6) {
                        ProgressView(value: book.clampedProgress)
                            .tint(accent)
                        Text("\(book.percentage)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        if !fileExists {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            chrome.opacity(0.6),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(alignment: .topTrailing) {
            Menu {
                LibraryBookMenuItems(book: book, onMove: onMove, onRemove: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.body)
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(6)
            .help("Move or remove")
        }
        .draggable(book.url.path)
        .contextMenu {
            LibraryBookMenuItems(book: book, onMove: onMove, onRemove: onRemove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.name), \(book.percentage) percent read, \(book.section.title)")
    }
}

private struct BookCover: View {
    let url: URL
    @ObservedObject var cache: LibraryCoverCache
    var width: CGFloat?
    var height: CGFloat

    init(url: URL, cache: LibraryCoverCache, width: CGFloat? = nil, height: CGFloat) {
        self.url = url
        self.cache = cache
        self.width = width
        self.height = height
    }

    var body: some View {
        Group {
            if let image = cache.image(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                    Image(systemName: "doc.richtext")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: width, height: height)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.2))
        )
        .task(id: url.path) {
            cache.load(url: url)
        }
    }
}

private struct LibraryBookMenuItems: View {
    let book: LibraryBook
    let onMove: (LibrarySection) -> Void
    let onRemove: () -> Void

    var body: some View {
        Menu("Move to") {
            ForEach(LibrarySection.allCases.filter { $0 != book.section }) { section in
                Button(section.title) {
                    onMove(section)
                }
            }
        }
        Divider()
        Button("Remove from Library", role: .destructive) {
            onRemove()
        }
    }
}
