import SwiftUI
import LaunchAtLogin

struct SettingsView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        TabView {
            GroupsSettingsView()
                .tabItem { Label("Groups", systemImage: "rectangle.3.group") }

            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 580, height: 400)
    }
}

// MARK: - Groups Tab

struct GroupsSettingsView: View {
    @Environment(AppState.self) var appState
    @State private var selectedGroupID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            // Group list
            VStack(spacing: 0) {
                List(selection: $selectedGroupID) {
                    ForEach(appState.groups) { group in
                        HStack(spacing: 8) {
                            Image(group.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                            Text(group.name)
                        }
                        .tag(group.id)
                    }
                }
                .listStyle(.bordered)

                HStack(spacing: 2) {
                    Button(action: addGroup) {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 24)
                    }
                    Button(action: removeSelected) {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 24)
                    }
                    .disabled(selectedGroupID == nil)

                    Spacer()

                    Button(action: moveSelectedUp) {
                        Image(systemName: "chevron.up")
                            .frame(width: 24, height: 24)
                    }
                    .disabled(!canMoveUp)
                    Button(action: moveSelectedDown) {
                        Image(systemName: "chevron.down")
                            .frame(width: 24, height: 24)
                    }
                    .disabled(!canMoveDown)
                }
                .padding(8)
            }
            .frame(width: 180)

            Divider()

            // Editor panel
            if let groupID = selectedGroupID,
               let group = appState.groups.first(where: { $0.id == groupID }) {
                DesktopGroupEditorView(group: group)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("Select or add a group")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .onAppear {
            if let pending = appState.pendingSelectGroupID {
                selectedGroupID = pending
                appState.pendingSelectGroupID = nil
            }
        }
        .onChange(of: appState.pendingSelectGroupID) {
            if let pending = appState.pendingSelectGroupID {
                selectedGroupID = pending
                appState.pendingSelectGroupID = nil
            }
        }
    }

    private func addGroup() {
        // Default to the currently active space on each monitor
        let currentSpaces = SpaceSwitcherService.getCurrentSpacePerDisplay()
        let displaySpaces = DesktopGroup.displaySpacesForCurrent(monitors: appState.monitors, currentSpaces: currentSpaces)

        let appearance = DesktopGroup.randomAppearance()
        let newGroup = DesktopGroup(name: "New Group", icon: appearance.icon,
                                    colorName: appearance.color, displaySpaces: displaySpaces)
        appState.addGroup(newGroup)
        selectedGroupID = newGroup.id
    }

    private func removeSelected() {
        guard let id = selectedGroupID,
              let group = appState.groups.first(where: { $0.id == id }) else { return }
        appState.deleteGroup(group)
        selectedGroupID = nil
    }

    private var selectedIndex: Int? {
        guard let id = selectedGroupID else { return nil }
        return appState.groups.firstIndex(where: { $0.id == id })
    }

    private var canMoveUp: Bool {
        guard let idx = selectedIndex else { return false }
        return idx > 0
    }

    private var canMoveDown: Bool {
        guard let idx = selectedIndex else { return false }
        return idx < appState.groups.count - 1
    }

    private func moveSelectedUp() {
        guard let idx = selectedIndex, idx > 0 else { return }
        appState.groups.swapAt(idx, idx - 1)
        appState.saveGroups()
    }

    private func moveSelectedDown() {
        guard let idx = selectedIndex, idx < appState.groups.count - 1 else { return }
        appState.groups.swapAt(idx, idx + 1)
        appState.saveGroups()
    }
}

// MARK: - General Tab

struct GeneralSettingsView: View {
    @Environment(AppState.self) var appState
    @State private var syncMessage: String?

    var body: some View {
        Form {
            HotkeySettingsView()
            LaunchAtLogin.Toggle("Launch at login")
            Toggle("Switch the whole group when a Space changes on one display (e.g. three-finger swipe)",
                   isOn: Binding(get: { appState.followEnabled }, set: { appState.followEnabled = $0 }))
            Toggle("Track windows to plan for display changes (experimental, dry run: logs only, moves nothing)",
                   isOn: Binding(get: { appState.trackWindowsEnabled }, set: { appState.trackWindowsEnabled = $0 }))
            Picker("Window snapshot interval", selection: Binding(get: { appState.snapshotIntervalSeconds },
                                                                  set: { appState.snapshotIntervalSeconds = $0 })) {
                ForEach([1, 5, 30, 60], id: \.self) { Text("\($0) s").tag($0) }
            }
            .disabled(!appState.trackWindowsEnabled)

            if Bundle.main.bundleIdentifier == "com.spaceswitcher.Spaces" {
                Divider()

                HStack {
                    Button("Sync from Development") {
                        syncFromDev()
                    }
                    if let message = syncMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }

    private func syncFromDev() {
        guard let devDefaults = UserDefaults(suiteName: "com.spaceswitcher.SpaceSwitcher"),
              let data = devDefaults.data(forKey: "desktopGroups"),
              let groups = try? JSONDecoder().decode([DesktopGroup].self, from: data) else {
            syncMessage = "No dev data found"
            return
        }
        appState.groups = groups
        appState.saveGroups()
        syncMessage = "Synced \(groups.count) groups"
    }
}
