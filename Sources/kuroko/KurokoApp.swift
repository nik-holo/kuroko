import SwiftUI
import Sparkle

@main
struct KurokoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Self.runFetchCLIIfRequested()
        Self.runCLIIfRequested()
    }

    var body: some Scene {
        // The app is fully menu-bar driven (see AppDelegate/StatusItemController);
        // an empty Settings scene satisfies SwiftUI's requirement for one scene.
        Settings { EmptyView() }
    }

    /// Headless web-link resolution for testing:
    /// `kuroko fetch [--dest <dir>] <url-or-webloc>...` downloads the image
    /// behind each link into --dest (default: the current directory).
    private static func runFetchCLIIfRequested() {
        var args = Array(CommandLine.arguments.dropFirst())
        guard args.first == "fetch" else { return }
        args.removeFirst()

        var destination = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        var targets: [URL] = []
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            if arg == "--dest" {
                guard let value = iterator.next() else { exit(2) }
                destination = URL(fileURLWithPath: value, isDirectory: true)
            } else if arg.hasPrefix("http://") || arg.hasPrefix("https://"), let url = URL(string: arg) {
                targets.append(url)
            } else if let url = WebLinkResolver.url(fromLinkFile: URL(fileURLWithPath: arg)) {
                targets.append(url)
            } else {
                FileHandle.standardError.write(Data("not a web URL or link file: \(arg)\n".utf8))
                exit(2)
            }
        }
        guard !targets.isEmpty else {
            FileHandle.standardError.write(Data("usage: kuroko fetch [--dest <dir>] <url-or-webloc>...\n".utf8))
            exit(2)
        }

        // App is @MainActor, so a plain Task would run on the main thread we
        // are about to block — detach it.
        let semaphore = DispatchSemaphore(value: 0)
        var failed = false
        Task.detached {
            for target in targets {
                do {
                    let saved = try await WebLinkResolver.download(target, into: destination)
                    print("\(target.absoluteString) -> \(saved.lastPathComponent)")
                } catch {
                    FileHandle.standardError.write(Data("failed: \(target.absoluteString): \(error)\n".utf8))
                    failed = true
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(failed ? 1 : 0)
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
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Sparkle needs a real bundle (SUFeedURL etc.) — skip when run bare.
        if Bundle.main.bundleIdentifier != nil {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
            )
        }

        let state = AppState()
        let controller = StatusItemController(appState: state)
        controller.updater = updaterController?.updater
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
