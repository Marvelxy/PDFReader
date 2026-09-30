import Foundation

/// A user-saved page bookmark. Persisted in UserDefaults as JSON
/// so bookmarks survive relaunches. Keyed by file name + page.
public struct PDFBookmark: Codable, Identifiable, Equatable {
    public var id: UUID
    public var fileName: String
    public var pageIndex: Int
    public var label: String
    public var createdAt: Date

    public init(fileName: String, pageIndex: Int, label: String) {
        self.id = UUID()
        self.fileName = fileName
        self.pageIndex = pageIndex
        self.label = label
        self.createdAt = Date()
    }
}

public final class BookmarkStore: ObservableObject {
    @Published public private(set) var bookmarks: [PDFBookmark] = []

    private let storageKey = "com.pdfreader.bookmarks.v1"

    public init() {
        load()
    }

    public func bookmarks(for fileName: String) -> [PDFBookmark] {
        bookmarks.filter { $0.fileName == fileName }.sorted { $0.pageIndex < $1.pageIndex }
    }

    public func isBookmarked(fileName: String, pageIndex: Int) -> Bool {
        bookmarks.contains { $0.fileName == fileName && $0.pageIndex == pageIndex }
    }

    public func toggle(fileName: String, pageIndex: Int) {
        if let existing = bookmarks.first(where: { $0.fileName == fileName && $0.pageIndex == pageIndex }) {
            remove(id: existing.id)
        } else {
            add(PDFBookmark(fileName: fileName, pageIndex: pageIndex, label: "Page \(pageIndex + 1)"))
        }
    }

    public func add(_ bookmark: PDFBookmark) {
        bookmarks.append(bookmark)
        save()
    }

    public func remove(id: PDFBookmark.ID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([PDFBookmark].self, from: data) {
            bookmarks = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
