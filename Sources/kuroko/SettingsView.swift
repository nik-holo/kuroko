import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Watched Folders") {
                if settings.folders.isEmpty {
                    Text("No folders — kuroko is idle.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.folders, id: \.self) { path in
                    HStack {
                        Text(displayName(for: path))
                        Spacer()
                        Button(role: .destructive) {
                            settings.removeFolder(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add Folder…") { addFolder() }
            }

            Section("Formats") {
                Toggle("WebP", isOn: $settings.convertWebP)
                Toggle("AVIF", isOn: $settings.convertAVIF)
                Toggle("HEIC / HEIF", isOn: $settings.convertHEIC)
                Toggle("Animated WebP → GIF", isOn: $settings.animatedToGIF)
                    .disabled(!settings.convertWebP)
            }

            Section("Output") {
                Toggle("Move originals to Trash", isOn: $settings.trashOriginals)
                VStack(alignment: .leading) {
                    Slider(value: $settings.jpegQuality, in: 0.5...1.0, step: 0.05) {
                        Text("JPEG quality")
                    }
                    Text("\(Int(settings.jpegQuality * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                Text("Launch at login only works when kuroko runs as an installed .app (see README).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func displayName(for path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        if panel.runModal() == .OK {
            for url in panel.urls {
                settings.addFolder(url.path)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
