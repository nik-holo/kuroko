import SwiftUI
import AppKit

/// Small confirm window shown when files are dropped on the menu bar icon
/// (or picked via "Convert Files…").
@MainActor
enum DropPanel {
    private static var window: NSWindow?

    static func show(files: [URL], engine: ConversionEngine) {
        let view = DropPanelView(files: files, engine: engine) { window?.close() }
        let hosting = NSHostingController(rootView: view)
        if let window {
            window.contentViewController = hosting
        } else {
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Convert Images"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.level = .floating
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct DropPanelView: View {
    let files: [URL]
    let engine: ConversionEngine
    let dismiss: () -> Void

    @State private var format: OutputFormat = .auto
    @State private var quality: Double = SettingsStore.shared.jpegQuality
    @State private var trashOriginals: Bool = SettingsStore.shared.trashOriginals
    @State private var destination: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(files.count == 1
                     ? files[0].lastPathComponent
                     : "\(files.count) images")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if files.count > 1 {
                    Text(files.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
                         + (files.count > 3 ? ", …" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Picker("Convert to", selection: $format) {
                ForEach(OutputFormat.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if format == .auto || format == .jpeg {
                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: $quality, in: 0.5...1.0, step: 0.05)
                    Text("JPEG quality: \(Int(quality * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Move originals to Trash", isOn: $trashOriginals)

            HStack(spacing: 6) {
                Text("Save to:")
                Text(destination.map { ($0.path as NSString).abbreviatingWithTildeInPath }
                     ?? "Same folder as original")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…") { chooseDestination() }
            }
            .font(.callout)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(files.count == 1 ? "Convert" : "Convert \(files.count) Files") {
                    engine.convertBatch(
                        files,
                        options: ConversionOptions(
                            format: format,
                            jpegQuality: quality,
                            animatedToGIF: true,
                            destinationDir: destination
                        ),
                        trashOriginals: trashOriginals
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        if panel.runModal() == .OK {
            destination = panel.url
        }
    }
}
