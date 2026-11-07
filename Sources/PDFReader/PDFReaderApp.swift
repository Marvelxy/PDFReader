import SwiftUI

/// Holds the `openWindow` action captured from a view so menu commands
/// (which can't read the environment) can open the About window.
enum AboutWindow {
    static var open: (() -> Void)?
}

enum SettingsWindow {
    static var open: (() -> Void)?
}

/// Print handler captured from the view so the File menu command (which
/// can't read the environment) can print the active document.
enum PrintAction {
    static var run: (() -> Void)?
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
                Button("Check for Updates…") { UpdateChecker.check() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindow.open?() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") { PrintAction.run?() }
                    .keyboardShortcut("p", modifiers: .command)
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
