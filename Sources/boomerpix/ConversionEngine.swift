import Foundation
import os

@MainActor
final class ConversionEngine: ObservableObject {
    private let logger = Logger(subsystem: "dev.nik.boomerpix", category: "engine")
    private var inFlight: Set<String> = []
    /// Keys of originals already converted in keep-originals mode, so folder
    /// events don't reconvert them. Key includes size+mtime so a re-downloaded
    /// file with the same name is picked up again.
    private var processed: Set<String> = []

    func handle(_ url: URL) {
        let path = url.path
        guard !inFlight.contains(path) else { return }
        guard FileManager.default.fileExists(atPath: path) else { return }
        if let key = fileKey(url), processed.contains(key) { return }
        inFlight.insert(path)

        Task { [weak self] in
            defer { self?.inFlight.remove(path) }
            guard await Self.waitUntilStable(url) else { return }

            let settings = SettingsStore.shared
            let quality = settings.jpegQuality
            let gif = settings.animatedToGIF

            let result: Result<ConversionOutcome, Error> = await Task.detached(priority: .utility) {
                Result { try ImageConverter.convert(url, jpegQuality: quality, animatedToGIF: gif) }
            }.value

            guard let self else { return }
            switch result {
            case .success(let outcome):
                if settings.trashOriginals {
                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    } catch {
                        self.logger.error("could not trash \(url.lastPathComponent): \(error.localizedDescription)")
                        if let key = self.fileKey(url) { self.processed.insert(key) }
                    }
                } else if let key = self.fileKey(url) {
                    self.processed.insert(key)
                }
                self.logger.info("converted \(url.lastPathComponent) -> \(outcome.output.lastPathComponent)")
            case .failure(let error):
                self.logger.error("failed to convert \(url.lastPathComponent): \(String(describing: error))")
            }
        }
    }

    /// Manual sweep of a folder. In keep-originals mode, files whose output
    /// already exists are skipped so repeated sweeps don't multiply copies.
    func sweep(folder: URL, extensions: Set<String>) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        for file in items where extensions.contains(file.pathExtension.lowercased()) {
            if !SettingsStore.shared.trashOriginals && outputExists(for: file) { continue }
            handle(file)
        }
    }

    private func outputExists(for url: URL) -> Bool {
        let base = url.deletingPathExtension()
        return ["jpg", "png", "gif"].contains { ext in
            FileManager.default.fileExists(atPath: base.appendingPathExtension(ext).path)
        }
    }

    private func fileKey(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        return "\(url.path)|\(size)|\(mtime.timeIntervalSince1970)"
    }

    /// Waits until the file size stops changing (browser may still be writing).
    private static func waitUntilStable(_ url: URL) async -> Bool {
        var lastSize: Int64?
        for _ in 0..<40 {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int64 else { return false }
            if let last = lastSize, last == size, size > 0 { return true }
            lastSize = size
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }
}
