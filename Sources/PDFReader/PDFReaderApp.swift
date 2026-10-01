import SwiftUI

/// Holds the `openWindow` action captured from a view so menu commands
/// (which can't read the environment) can open the About window.
enum AboutWindow {
    static var open: (() -> Void)?
}

@main
struct PDFReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .textEditing) { EmptyView() }
            CommandGroup(replacing: .appInfo) {
                Button("About PDFReader") { AboutWindow.open?() }
            }
        }

        Window("About PDFReader", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
