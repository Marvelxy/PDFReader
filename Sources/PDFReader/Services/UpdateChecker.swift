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
                            if let u = URL(string: url) {
                                UpdateDownloader.shared.download(u)
                            }
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

/// Downloads an update DMG into ~/Downloads with a progress window and
/// mounts it when finished.
@MainActor
final class UpdateDownloader: NSObject, URLSessionDownloadDelegate {
    static let shared = UpdateDownloader()

    private var task: URLSessionDownloadTask?
    private var session: URLSession {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }
    private var panel: NSPanel?
    private var label = NSTextField(labelWithString: "Downloading update…")
    private var progress = NSProgressIndicator()
    private var destinationName = "PDFReader-update.dmg"

    func download(_ url: URL) {
        destinationName = url.lastPathComponent
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 88),
            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Downloading Update"
        panel.center()
        label.stringValue = "Downloading " + destinationName + "…"
        label.frame = NSRect(x: 20, y: 52, width: 320, height: 20)
        progress.frame = NSRect(x: 20, y: 24, width: 320, height: 20)
        progress.isIndeterminate = false
        progress.doubleValue = 0
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 130, y: -2, width: 100, height: 20)
        cancel.bezelStyle = .texturedRounded
        let view = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        view.addSubview(label); view.addSubview(progress); view.addSubview(cancel)
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
        task = session.downloadTask(with: url)
        task?.resume()
    }

    @objc private func cancel() {
        task?.cancel()
        finish(error: NSError(domain: "UpdateDownloader", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Download cancelled."]))
    }

    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let fraction = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in self.progress.doubleValue = fraction }
    }

    nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let dest = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(downloadTask.originalRequest?.url?.lastPathComponent ?? "PDFReader-update.dmg")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            Task { @MainActor in
                self.panel?.orderOut(nil)
                NSWorkspace.shared.open(dest)
            }
        } catch {
            Task { @MainActor in self.finish(error: error) }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        if let error {
            Task { @MainActor in self.finish(error: error) }
        }
    }

    private func finish(error: Error) {
        panel?.orderOut(nil)
        let alert = NSAlert()
        alert.messageText = "Download Failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
