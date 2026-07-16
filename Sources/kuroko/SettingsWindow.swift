import SwiftUI
import AppKit

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(SettingsStore.shared)
            )
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "kuroko Settings"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
