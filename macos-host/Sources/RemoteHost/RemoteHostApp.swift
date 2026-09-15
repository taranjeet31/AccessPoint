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
        swizzleReportException()

        // Set accessory policy so it runs as a menu-bar item without Dock presence
        NSApp.setActivationPolicy(.accessory)

        let controller = MenuBarController()
        self.menuBarController = controller
        controller.start()
        controller.showPairingWindow()
    }

    private func swizzleReportException() {
        let originalSelector = #selector(NSApplication.reportException(_:))
        let swizzledSelector = #selector(NSApplication.customReportException(_:))

        guard let originalMethod = class_getInstanceMethod(NSApplication.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSApplication.self, swizzledSelector) else {
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            self.menuBarController?.endActiveSession()
        }
    }
}

extension NSApplication {
    @objc func customReportException(_ exception: NSException) {
        print("========================================")
        print("🔥 APPKIT EXCEPTION CAPTURED:")
        print("Name: \(exception.name.rawValue)")
        print("Reason: \(exception.reason ?? "No reason provided")")
        print("UserInfo: \(exception.userInfo ?? [:])")
        print("Call Stack:")
        for symbol in exception.callStackSymbols {
            print("  \(symbol)")
        }
        print("========================================")
        fflush(stdout)
        fflush(stderr)
        self.customReportException(exception)
    }
}
