import SwiftUI

/// Holds the `openWindow` action captured from a view so menu commands
/// (which can't read the environment) can open the About window.
enum AboutWindow {
    static var open: (() -> Void)?
}

enum SettingsWindow {
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
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindow.open?() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .help) {
                Button("Check for Updates…") { UpdateChecker.check() }
            }
        }

        Window("About PDFReader", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}
