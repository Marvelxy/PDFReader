import AppKit

/// Polls GitHub for the latest release and prompts the user to install it.
enum UpdateChecker {
    private struct Release: Decodable {
        let tagName: String
        let htmlUrl: String
        let assets: [Asset]
        struct Asset: Decodable { let browserDownloadUrl: String }
    }

    private static let api = URL(
        string: "https://api.github.com/repos/Marvelxy/PDFReader/releases/latest")!

    static func check() {
        Task {
            do {
                var request = URLRequest(url: api)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, _) = try await URLSession.shared.data(for: request)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let release = try decoder.decode(Release.self, from: data)
                let latest = release.tagName.trimmingCharacters(
                    in: CharacterSet(charactersIn: "vV"))
                let current =
                    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                        as? String) ?? "0"
                await MainActor.run {
                    if compare(latest, isNewerThan: current) {
                        let alert = NSAlert()
                        alert.messageText = "Update Available"
                        alert.informativeText =
                            "PDFReader \(release.tagName) is available — you have \(current)."
                        alert.addButton(withTitle: "Download")
                        alert.addButton(withTitle: "Later")
                        if alert.runModal() == .alertFirstButtonReturn {
                            let url = release.assets.first?.browserDownloadUrl ?? release.htmlUrl
                            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                        }
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "Up to Date"
                        alert.informativeText = "PDFReader \(current) is the latest version."
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Update Check Failed"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    /// Numeric "a.b.c" comparison; returns true if `latest` is strictly greater.
    private static func compare(_ latest: String, isNewerThan current: String) -> Bool {
        let a = latest.split(separator: ".").compactMap {
            Int($0.split(separator: "-").first ?? "")
        }
        let b = current.split(separator: ".").compactMap {
            Int($0.split(separator: "-").first ?? "")
        }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
