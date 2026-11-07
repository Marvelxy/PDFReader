import Foundation

/// Shelf a book belongs to on the Library page.
public enum LibrarySection: String, Codable, CaseIterable, Identifiable {
    case currentlyReading
    case wantToRead
    case finished

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .currentlyReading: return "Currently reading"
        case .wantToRead: return "Want to read"
        case .finished: return "Finished"
        }
    }

    public var symbol: String {
        switch self {
        case .currentlyReading: return "book"
        case .wantToRead: return "bookmark"
        case .finished: return "checkmark.circle"
        }
    }
}

/// A PDF tracked by the Library. Progress is the fraction read (0...1),
/// mirroring the viewer's reading-progress percentage.
public struct LibraryBook: Codable, Identifiable, Hashable {
    public var url: URL
    public var section: LibrarySection
    public var progress: Double
    public var lastRead: Date

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var percentage: Int { Int((clampedProgress * 100).rounded()) }

    public var clampedProgress: Double { min(max(progress, 0), 1) }

    public init(
        url: URL,
        section: LibrarySection = .currentlyReading,
        progress: Double = 0,
        lastRead: Date = Date()
    ) {
        self.url = url
        self.section = section
        self.progress = min(max(progress, 0), 1)
        self.lastRead = lastRead
    }
}

/// Persisted list of books grouped into reading shelves. Books enter the
/// library when opened (into Currently reading) and keep their section
/// until the user moves them.
public final class LibraryStore: ObservableObject {
    @Published public private(set) var books: [LibraryBook] = []

    private let storageKey = "com.pdfreader.library.v1"

    public init() {
        load()
    }

    /// Books on a shelf, most recently read first.
    public func books(in section: LibrarySection) -> [LibraryBook] {
        books
            .filter { $0.section == section }
            .sorted { $0.lastRead > $1.lastRead }
    }

    /// Records an open/read: new books join Currently reading, existing
    /// books keep their shelf and just refresh progress + recency.
    public func record(url: URL, progress: Double) {
        let clamped = min(max(progress, 0), 1)
        if let index = books.firstIndex(where: { $0.url.path == url.path }) {
            books[index].progress = clamped
            books[index].lastRead = Date()
        } else {
            books.append(LibraryBook(url: url, section: .currentlyReading, progress: clamped))
        }
        save()
    }

    public func move(_ url: URL, to section: LibrarySection) {
        guard let index = books.firstIndex(where: { $0.url.path == url.path }),
              books[index].section != section
        else { return }
        books[index].section = section
        save()
    }

    public func remove(_ url: URL) {
        let before = books.count
        books.removeAll { $0.url.path == url.path }
        if books.count != before { save() }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([LibraryBook].self, from: data) {
            books = decoded.map {
                LibraryBook(
                    url: $0.url,
                    section: $0.section,
                    progress: $0.progress,
                    lastRead: $0.lastRead
                )
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(books) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
