import SwiftUI

@main
struct OneScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = DisplayController()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(controller)
                .onAppear { controller.refresh() }
        } label: {
            Image(systemName: controller.mode.isOneScreen ? "display" : "display.2")
                .accessibilityLabel("OneScreen")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Handles `onescreen://one`, `onescreen://two` and `onescreen://toggle` so the
/// switch can be driven from Shortcuts, Raycast, or `open onescreen://toggle`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let commandNotification = Notification.Name("com.heyitsbrian.onescreen.command")

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let host = url.host?.lowercased() else { continue }
            NotificationCenter.default.post(name: AppDelegate.commandNotification, object: nil, userInfo: ["command": host])
        }
    }
}
