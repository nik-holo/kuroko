import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Text(appState.paused
             ? "Paused"
             : "Watching \(appState.watchedFolderCount) folder\(appState.watchedFolderCount == 1 ? "" : "s")")

        Button(appState.paused ? "Resume" : "Pause") {
            appState.paused.toggle()
        }

        Button("Convert Now") {
            appState.convertNow()
        }

        Divider()

        Button("Settings…") {
            SettingsWindow.show()
        }

        Divider()

        Button("Quit boomerpix") {
            NSApplication.shared.terminate(nil)
        }
    }
}
