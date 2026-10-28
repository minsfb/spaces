import SwiftUI

struct DesktopGroupEditorView: View {
    @Environment(AppState.self) var appState
    let group: DesktopGroup

    @State private var name: String = ""
    @State private var icon: String = "Labtop"
    @State private var spaceIndices: [String: Int] = [:]   // monitor.id -> 1-based index (UI state only)
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                LabeledContent("Group Name:") {
                    TextField("", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFocused)
                }

                LabeledContent("Icon:") {
                    IconPicker(selectedIcon: $icon)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Monitor \u{2192} Space Mapping")
                    .font(.headline)

                ForEach(appState.monitors) { monitor in
                    MonitorMappingView(
                        monitor: monitor,
                        spaceNumber: Binding(
                            get: { spaceIndices[monitor.id] ?? 1 },
                            set: { spaceIndices[monitor.id] = $0 }
                        ),
                        currentGroupID: group.id,
                        allGroups: appState.groups
                    )
                }

                if appState.monitors.isEmpty {
                    Text("No monitors detected")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Apply") {
                    var updated = group
                    updated.name = name
                    updated.icon = icon
                    for monitor in appState.monitors {
                        updated.setSpaceIndex(spaceIndices[monitor.id] ?? 1, on: monitor)
                    }
                    appState.updateGroup(updated)
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            name = group.name
            icon = group.icon
            loadIndices()
            if group.name == "New Group" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isNameFocused = true
                }
            }
        }
        .onChange(of: group.id) {
            name = group.name
            icon = group.icon
            loadIndices()
            if group.name == "New Group" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isNameFocused = true
                }
            }
        }
    }

    private func loadIndices() {
        var result: [String: Int] = [:]
        for monitor in appState.monitors { result[monitor.id] = group.spaceIndex(on: monitor) ?? 1 }
        spaceIndices = result
    }
}
