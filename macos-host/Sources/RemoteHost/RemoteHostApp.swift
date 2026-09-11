import SwiftUI
import AppKit
import RemoteHostCore

@main
struct RemoteHostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set accessory policy so it runs as a menu-bar item without Dock presence
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            let controller = MenuBarController()
            self.menuBarController = controller
            controller.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            self.menuBarController?.endActiveSession()
        }
    }
}
