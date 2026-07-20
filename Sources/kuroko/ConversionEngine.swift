import Foundation
import os
import AppKit
import UserNotifications

/// One completed conversion event, remembered so it can be undone.
struct UndoRecord {
    struct Item {
        let originalURL: URL          // where the source file lived
        let trashedURL: URL?          // where it went in the Trash (nil = kept)
        let outputURL: URL
    }
    let items: [Item]
}

@MainActor
final class ConversionEngine: ObservableObject {
    private let logger = Logger(subsystem: "dev.nik.kuroko", category: "engine")
    private var inFlight: Set<String> = []
    /// Keys of originals already converted in keep-originals mode, so folder
    /// events don't reconvert them. Key includes size+mtime so a re-downloaded
    /// file with the same name is picked up again.
    private var processed: Set<String> = []
    /// The most recent conversion event (single watched file or a whole drop batch).
    @Published private(set) var lastUndo: UndoRecord?

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
            var options = ConversionOptions(jpegQuality: settings.jpegQuality,
                                            animatedToGIF: settings.animatedToGIF)
            options.stripMetadata = settings.stripMetadata

            let result: Result<ConversionOutcome, Error> = await Task.detached(priority: .utility) {
                Result { try ImageConverter.convert(url, options: options) }
            }.value

            guard let self else { return }
            switch result {
            case .success(let outcome):
                var trashedURL: URL?
                if settings.trashOriginals {
                    do {
                        var resulting: NSURL?
                        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                        trashedURL = resulting as URL?
                    } catch {
                        self.logger.error("could not trash \(url.lastPathComponent): \(error.localizedDescription)")
                        if let key = self.fileKey(url) { self.processed.insert(key) }
                    }
                } else if let key = self.fileKey(url) {
                    self.processed.insert(key)
                }
                self.recordSuccess(items: [UndoRecord.Item(originalURL: url, trashedURL: trashedURL, outputURL: outcome.output)])
                self.notify(body: "\(url.lastPathComponent) → \(outcome.output.lastPathComponent)")
                self.logger.info("converted \(url.lastPathComponent) -> \(outcome.output.lastPathComponent)")
            case .failure(let error):
                self.logger.error("failed to convert \(url.lastPathComponent): \(String(describing: error))")
            }
        }
    }

    /// Converts user-dropped files with explicit options. No stability wait —
    /// dropped files are complete — and no processed-set bookkeeping, since the
    /// user explicitly asked for these conversions.
    func convertBatch(_ files: [URL], options: ConversionOptions, trashOriginals: Bool) {
        Task { [weak self] in
            var undoItems: [UndoRecord.Item] = []
            var failures = 0
            for file in files {
                let result: Result<ConversionOutcome, Error> = await Task.detached(priority: .userInitiated) {
                    Result { try ImageConverter.convert(file, options: options) }
                }.value
                guard let self else { return }
                switch result {
                case .success(let outcome):
                    var trashedURL: URL?
                    if trashOriginals {
                        var resulting: NSURL?
                        try? FileManager.default.trashItem(at: file, resultingItemURL: &resulting)
                        trashedURL = resulting as URL?
                    }
                    undoItems.append(UndoRecord.Item(originalURL: file, trashedURL: trashedURL, outputURL: outcome.output))
                    self.logger.info("drop-convert \(file.lastPathComponent) -> \(outcome.output.lastPathComponent)")
                case .failure(let error):
                    failures += 1
                    self.logger.error("drop-convert failed \(file.lastPathComponent): \(String(describing: error))")
                }
            }
            guard let self else { return }
            if !undoItems.isEmpty {
                self.recordSuccess(items: undoItems)
                let summary = undoItems.count == 1
                    ? "\(undoItems[0].originalURL.lastPathComponent) → \(undoItems[0].outputURL.lastPathComponent)"
                    : "Converted \(undoItems.count) images" + (failures > 0 ? " (\(failures) failed)" : "")
                self.notify(body: summary)
            }
        }
    }

    /// Reverts the most recent conversion: outputs go to the Trash, and
    /// originals that were trashed are restored to where they came from.
    /// Restored originals are marked processed — otherwise the watcher sees
    /// them reappear and immediately converts them again, undoing the undo.
    /// (Dropping the file on the icon still converts it, deliberately.)
    func undoLast() {
        guard let record = lastUndo else { return }
        lastUndo = nil
        for item in record.items {
            try? FileManager.default.trashItem(at: item.outputURL, resultingItemURL: nil)
            if let trashed = item.trashedURL,
               !FileManager.default.fileExists(atPath: item.originalURL.path) {
                try? FileManager.default.moveItem(at: trashed, to: item.originalURL)
            }
            if let key = fileKey(item.originalURL) {
                processed.insert(key)
            }
        }
        logger.info("undid last conversion (\(record.items.count) file(s))")
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

    // MARK: bookkeeping

    private func recordSuccess(items: [UndoRecord.Item]) {
        lastUndo = UndoRecord(items: items)
        SettingsStore.shared.totalConverted += items.count
    }

    /// Posts a user notification if enabled. Only possible when running as a
    /// bundled .app — UNUserNotificationCenter requires a bundle identifier.
    private func notify(body: String) {
        guard SettingsStore.shared.notifyOnConversion,
              Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "kuroko"
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
