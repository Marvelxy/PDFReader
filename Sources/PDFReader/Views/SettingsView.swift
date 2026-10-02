import SwiftUI

struct SettingsView: View {
    @AppStorage("com.pdfreader.remembersLastPosition.v1")
    private var remembersLastPosition = true

    var body: some View {
        Form {
            Section("Opening Files") {
                Toggle("Remember where I left off in each file", isOn: $remembersLastPosition)
                    .toggleStyle(.switch)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 160)
        .padding()
    }
}
