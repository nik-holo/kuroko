import SwiftUI

@main
struct BoomerpixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        Self.runCLIIfRequested()
        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(appState)
                .environmentObject(SettingsStore.shared)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }

    /// Headless mode for testing: `boomerpix convert <file>...` converts and exits.
    private static func runCLIIfRequested() {
        let args = CommandLine.arguments
        guard args.count >= 3, args[1] == "convert" else { return }
        let settings = SettingsStore.shared
        var failed = false
        for path in args.dropFirst(2) {
            let url = URL(fileURLWithPath: path)
            do {
                let outcome = try ImageConverter.convert(
                    url,
                    jpegQuality: settings.jpegQuality,
                    animatedToGIF: settings.animatedToGIF
                )
                print("\(url.lastPathComponent) -> \(outcome.output.lastPathComponent) [\(outcome.kind)]")
            } catch {
                FileHandle.standardError.write(Data("failed: \(path): \(error)\n".utf8))
                failed = true
            }
        }
        exit(failed ? 1 : 0)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
