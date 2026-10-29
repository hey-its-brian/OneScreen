import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var controller: DisplayController
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Text(controller.statusText)
        if let error = controller.lastError ?? loginError {
            Text(error)
        }

        Divider()

        Button(controller.mode.isOneScreen ? "Use Two Screens" : "Use One Screen") {
            controller.toggle()
        }
        .disabled(!controller.canToggle)

        if controller.mode == .single && PrivateAPI.canDisableDisplays {
            Button("Look for Hidden Displays") { controller.lookForHiddenDisplays() }
        }

        Divider()

        Picker("One Screen Means", selection: $controller.method) {
            ForEach(OneScreenMethod.allCases) { method in
                Text(method.title).tag(method)
            }
        }
        .pickerStyle(.inline)
        .disabled(!PrivateAPI.canDisableDisplays)

        Divider()

        Section("Displays") {
            ForEach(controller.displays) { display in
                Text("\(display.name) · \(controller.positionLabel(for: display)) · \(display.pixelSize)")
            }
        }

        Divider()

        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    try LoginItem.setEnabled(enabled)
                    loginError = nil
                } catch {
                    loginError = "Launch at Login failed: \(error.localizedDescription)"
                    launchAtLogin = LoginItem.isEnabled
                }
            }

        Button("Quit OneScreen") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
