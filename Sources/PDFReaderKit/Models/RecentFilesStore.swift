import Foundation

/// A recently opened PDF. Only the URL + timestamp are persisted;
/// the display name derives from the file name.
public struct RecentFile: Codable, Identifiable, Hashable {
    public var url: URL
    public var lastOpened: Date

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }

    public init(url: URL, lastOpened: Date = Date()) {
        self.url = url
        self.lastOpened = lastOpened
    }
}

public extension RecentFile {
    /// Friendly age with minute-level precision ("1 min ago") — never
    /// second-level ("1 min, 14 secs").
    static func ageDescription(for date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0 ..< 60:
            return "Just now"
        case 60 ..< 3_600:
            return "\(seconds / 60) min ago"
        case 3_600 ..< 86_400:
            return "\(seconds / 3_600) hr ago"
        case 86_400 ..< 604_800:
            let days = seconds / 86_400
            return days == 1 ? "1 day ago" : "\(days) days ago"
        default:
            return RecentFilesStore.olderDateFormatter.string(from: date)
        }
    }
}

/// Newest-first, de-duplicated, capped list of opened PDFs.
/// Persisted in UserDefaults as JSON so it survives relaunches.
public final class RecentFilesStore: ObservableObject {
    public static let maximumCount = 10

    /// Short-date formatter for files older than a week ("Sep 28, 2026").
    static let olderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    @Published public private(set) var items: [RecentFile] = []

    private let storageKey = "com.pdfreader.recentFiles.v1"

    public init() {
        load()
    }

    /// Records an open: bumps an existing entry to the top, else inserts.
    public func record(_ url: URL) {
        items.removeAll { $0.url.path == url.path }
        items.insert(RecentFile(url: url), at: 0)
        if items.count > Self.maximumCount {
            items = Array(items.prefix(Self.maximumCount))
        }
        save()
    }

    public func remove(_ url: URL) {
        items.removeAll { $0.url.path == url.path }
        save()
    }

    public func clear() {
        items = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([RecentFile].self, from: data) {
            items = Array(decoded.prefix(Self.maximumCount))
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
