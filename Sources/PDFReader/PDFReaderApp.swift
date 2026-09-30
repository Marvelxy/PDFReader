import SwiftUI

@main
struct PDFReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .textEditing) { EmptyView() }
        }
    }
}
