import AppKit
import UniformTypeIdentifiers
import Sparkle

/// AppKit-based menu bar item. We use NSStatusItem instead of SwiftUI's
/// MenuBarExtra because the status button must accept file drops, which
/// MenuBarExtra does not support.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let appState: AppState
    /// Sparkle updater; nil when running unbundled (swift run / debug binary).
    var updater: SPUUpdater?

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = MenuBarIcon.image
        menu.delegate = self
        statusItem.menu = menu

        if let button = statusItem.button {
            let dropView = StatusDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.onDrop = { [weak self] urls in self?.handleDrop(urls) }
            dropView.onClick = { [weak self] in self?.statusItem.button?.performClick(nil) }
            button.addSubview(dropView)
        }
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let count = appState.watchedFolderCount
        let status = appState.paused
            ? "Paused"
            : "Watching \(count) folder\(count == 1 ? "" : "s")"
        let statusLine = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        let total = SettingsStore.shared.totalConverted
        if total > 0 {
            let counter = NSMenuItem(
                title: "\(total.formatted()) image\(total == 1 ? "" : "s") converted",
                action: nil, keyEquivalent: ""
            )
            counter.isEnabled = false
            menu.addItem(counter)
        }

        menu.addItem(item(appState.paused ? "Resume" : "Pause", #selector(togglePause)))
        menu.addItem(item("Convert Now", #selector(convertNow)))
        menu.addItem(item("Convert Files…", #selector(chooseFiles)))
        if appState.engine.lastUndo != nil {
            menu.addItem(item("Undo Last Conversion", #selector(undoLast)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings)))
        if updater != nil {
            menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit kuroko", #selector(quit)))
    }

    private func item(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func togglePause() { appState.paused.toggle() }
    @objc private func convertNow() { appState.convertNow() }
    @objc private func undoLast() { appState.engine.undoLast() }
    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updater?.checkForUpdates()
    }

    @objc private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .folder]
        panel.prompt = "Convert"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            handleDrop(panel.urls)
        }
    }

    // MARK: drops

    func handleDrop(_ urls: [URL]) {
        let files = DropExpander.expand(urls)
        guard !files.isEmpty else { return }
        DropPanel.show(files: files, engine: appState.engine)
    }
}

/// Handles the Finder right-click Services entry ("Convert with kuroko").
/// Declared via NSServices in Info.plist; registered as NSApp.servicesProvider.
final class ServiceProvider: NSObject {
    private let onFiles: @MainActor ([URL]) -> Void

    init(onFiles: @escaping @MainActor ([URL]) -> Void) {
        self.onFiles = onFiles
    }

    @objc func convertFiles(_ pasteboard: NSPasteboard, userData: String,
                            error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            self.onFiles(urls)
        }
    }
}

/// Transparent overlay on the status button that accepts file drags and
/// forwards clicks to the button (so the menu still opens normally).
final class StatusDropView: NSView {
    var onDrop: ([URL]) -> Void = { _ in }
    var onClick: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) { onClick() }
    override func rightMouseDown(with event: NSEvent) { onClick() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasFileURLs(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }

    private func hasFileURLs(_ info: NSDraggingInfo) -> Bool {
        info.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }
}

/// Expands a dropped selection into convertible image files: folders
/// contribute their top-level images (not recursive).
enum DropExpander {
    static func expand(_ urls: [URL]) -> [URL] {
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let items = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                )) ?? []
                files.append(contentsOf: items.filter(isImage).sorted { $0.lastPathComponent < $1.lastPathComponent })
            } else if isImage(url) {
                files.append(url)
            }
        }
        return files
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image)
    }
}
