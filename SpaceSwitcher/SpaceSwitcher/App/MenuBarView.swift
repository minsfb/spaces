import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ForEach(appState.groups) { group in
            Button {
                appState.switchToGroup(group)
            } label: {
                HStack {
                    Image(group.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text(group.name)
                    if appState.activeGroupID == group.id {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
        }

        if !appState.groups.isEmpty {
            Divider()
        }

        Button("New Group\u{2026}") {
            addGroupFromMenu()
        }

        Button("Settings\u{2026}") {
            openSettings()
            NotificationCenter.default.post(name: .showSettings, object: nil)
        }

        Divider()

        Button("Quit Spaces") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func addGroupFromMenu() {
        let currentSpaces = SpaceSwitcherService.getCurrentSpacePerDisplay()
        let displaySpaces = DesktopGroup.displaySpacesForCurrent(monitors: appState.monitors, currentSpaces: currentSpaces)

        let appearance = DesktopGroup.randomAppearance()
        let newGroup = DesktopGroup(name: "New Group", icon: appearance.icon,
                                    colorName: appearance.color, displaySpaces: displaySpaces)
        appState.addGroup(newGroup)
        appState.pendingSelectGroupID = newGroup.id

        openSettings()
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }
}
