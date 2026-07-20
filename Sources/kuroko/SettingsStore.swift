import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Keys {
        static let folders = "watchedFolders"
        static let trashOriginals = "trashOriginals"
        static let jpegQuality = "jpegQuality"
        static let convertWebP = "convertWebP"
        static let convertAVIF = "convertAVIF"
        static let convertHEIC = "convertHEIC"
        static let animatedToGIF = "animatedToGIF"
        static let stripMetadata = "stripMetadata"
        static let notifyOnConversion = "notifyOnConversion"
        static let totalConverted = "totalConverted"
    }

    @Published var folders: [String] { didSet { defaults.set(folders, forKey: Keys.folders) } }
    @Published var trashOriginals: Bool { didSet { defaults.set(trashOriginals, forKey: Keys.trashOriginals) } }
    @Published var jpegQuality: Double { didSet { defaults.set(jpegQuality, forKey: Keys.jpegQuality) } }
    @Published var convertWebP: Bool { didSet { defaults.set(convertWebP, forKey: Keys.convertWebP) } }
    @Published var convertAVIF: Bool { didSet { defaults.set(convertAVIF, forKey: Keys.convertAVIF) } }
    @Published var convertHEIC: Bool { didSet { defaults.set(convertHEIC, forKey: Keys.convertHEIC) } }
    @Published var animatedToGIF: Bool { didSet { defaults.set(animatedToGIF, forKey: Keys.animatedToGIF) } }
    @Published var stripMetadata: Bool { didSet { defaults.set(stripMetadata, forKey: Keys.stripMetadata) } }
    @Published var notifyOnConversion: Bool { didSet { defaults.set(notifyOnConversion, forKey: Keys.notifyOnConversion) } }
    @Published var totalConverted: Int { didSet { defaults.set(totalConverted, forKey: Keys.totalConverted) } }

    private let defaults = UserDefaults.standard

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultFolders = [
            home.appendingPathComponent("Downloads").path,
            home.appendingPathComponent("Desktop").path,
        ]
        defaults.register(defaults: [
            Keys.folders: defaultFolders,
            Keys.trashOriginals: true,
            Keys.jpegQuality: 0.85,
            Keys.convertWebP: true,
            Keys.convertAVIF: true,
            Keys.convertHEIC: true,
            Keys.animatedToGIF: true,
            Keys.stripMetadata: false,
            Keys.notifyOnConversion: false,
            Keys.totalConverted: 0,
        ])
        folders = defaults.stringArray(forKey: Keys.folders) ?? defaultFolders
        trashOriginals = defaults.bool(forKey: Keys.trashOriginals)
        jpegQuality = defaults.double(forKey: Keys.jpegQuality)
        convertWebP = defaults.bool(forKey: Keys.convertWebP)
        convertAVIF = defaults.bool(forKey: Keys.convertAVIF)
        convertHEIC = defaults.bool(forKey: Keys.convertHEIC)
        animatedToGIF = defaults.bool(forKey: Keys.animatedToGIF)
        stripMetadata = defaults.bool(forKey: Keys.stripMetadata)
        notifyOnConversion = defaults.bool(forKey: Keys.notifyOnConversion)
        totalConverted = defaults.integer(forKey: Keys.totalConverted)
    }

    var enabledExtensions: Set<String> {
        var exts = Set<String>()
        if convertWebP { exts.insert("webp") }
        if convertAVIF { exts.insert("avif") }
        if convertHEIC { exts.formUnion(["heic", "heif"]) }
        return exts
    }

    func addFolder(_ path: String) {
        guard !folders.contains(path) else { return }
        folders.append(path)
    }

    func removeFolder(_ path: String) {
        folders.removeAll { $0 == path }
    }
}
