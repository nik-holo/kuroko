import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var paused = false

    let engine = ConversionEngine()
    private var watchers: [DirectoryWatcher] = []
    private var cancellables: Set<AnyCancellable> = []

    init() {
        rebuildWatchers()
        SettingsStore.shared.$folders
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildWatchers() }
            .store(in: &cancellables)
    }

    var watchedFolderCount: Int { watchers.count }

    func convertNow() {
        let settings = SettingsStore.shared
        for folder in settings.folders {
            engine.sweep(folder: URL(fileURLWithPath: folder), extensions: settings.enabledExtensions)
        }
    }

    private func rebuildWatchers() {
        watchers.forEach { $0.stop() }
        watchers = SettingsStore.shared.folders.compactMap { path in
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return DirectoryWatcher(directory: url) { [weak self] changedURLs in
                self?.handleChanges(changedURLs)
            }
        }
    }

    private func handleChanges(_ urls: [URL]) {
        guard !paused else { return }
        let extensions = SettingsStore.shared.enabledExtensions
        for url in urls {
            let name = url.lastPathComponent
            guard !name.hasPrefix("."), extensions.contains(url.pathExtension.lowercased()) else { continue }
            engine.handle(url)
        }
    }
}
