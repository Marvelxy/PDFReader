import SwiftUI

/// App menu → About window content.
struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.pages")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("PDFReader for Mac")
                .font(.title)
            Text("Version \(version) (\(build))")
                .foregroundStyle(.secondary)
            Divider().frame(maxWidth: 280)
            VStack(alignment: .leading, spacing: 6) {
                Text("By Marvelus Akpotu")
                Link(
                    "still4marvelous@gmail.com",
                    destination: URL(string: "mailto:still4marvelous@gmail.com")!)
                Link(
                    "github.com/Marvelxy", destination: URL(string: "https://github.com/Marvelxy")!)
            }
            Text("Licensed under the GPL-3.0 license.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 360)
    }
}
