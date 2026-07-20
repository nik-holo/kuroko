import SwiftUI

@main
struct KurokoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Self.runCLIIfRequested()
    }

    var body: some Scene {
        // The app is fully menu-bar driven (see AppDelegate/StatusItemController);
        // an empty Settings scene satisfies SwiftUI's requirement for one scene.
        Settings { EmptyView() }
    }

    /// Headless mode for testing:
    /// `kuroko convert [--format auto|jpeg|png|gif] [--dest <dir>] <file>...`
    private static func runCLIIfRequested() {
        var args = Array(CommandLine.arguments.dropFirst())
        guard args.first == "convert" else { return }
        args.removeFirst()

        var options = ConversionOptions(jpegQuality: SettingsStore.shared.jpegQuality,
                                        animatedToGIF: SettingsStore.shared.animatedToGIF)
        var paths: [String] = []
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--format":
                guard let value = iterator.next(), let format = OutputFormat(rawValue: value) else {
                    FileHandle.standardError.write(Data("usage: --format auto|jpeg|png|gif\n".utf8))
                    exit(2)
                }
                options.format = format
            case "--dest":
                guard let value = iterator.next() else { exit(2) }
                options.destinationDir = URL(fileURLWithPath: value, isDirectory: true)
            case "--max-dimension":
                guard let value = iterator.next(), let dimension = Int(value), dimension > 0 else { exit(2) }
                options.maxDimension = dimension
            case "--max-mb":
                guard let value = iterator.next(), let mb = Double(value), mb > 0 else { exit(2) }
                options.maxFileBytes = Int(mb * 1_048_576)
            case "--strip-metadata":
                options.stripMetadata = true
            default:
                paths.append(arg)
            }
        }
        guard !paths.isEmpty else { return }

        var failed = false
        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                let outcome = try ImageConverter.convert(url, options: options)
                print("\(url.lastPathComponent) -> \(outcome.output.lastPathComponent) [\(outcome.kind)]")
            } catch {
                FileHandle.standardError.write(Data("failed: \(path): \(error)\n".utf8))
                failed = true
            }
        }
        exit(failed ? 1 : 0)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusController: StatusItemController?
    private var serviceProvider: ServiceProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let state = AppState()
        let controller = StatusItemController(appState: state)
        appState = state
        statusController = controller

        // Finder right-click → Services → "Convert with kuroko"
        let provider = ServiceProvider { [weak controller] urls in
            controller?.handleDrop(urls)
        }
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
    }
}
