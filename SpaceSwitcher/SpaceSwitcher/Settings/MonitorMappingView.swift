import SwiftUI

struct MonitorMappingView: View {
    let monitor: MonitorInfo
    @Binding var spaceNumber: Int
    let currentGroupID: UUID
    let allGroups: [DesktopGroup]

    var body: some View {
        HStack {
            Text(monitor.label)
                .frame(width: 80, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            Picker("", selection: $spaceNumber) {
                ForEach(monitor.spaceIndices, id: \.self) { index in
                    Text(labelForIndex(index)).tag(index)
                }
            }
            .labelsHidden()
            .frame(width: 220)
        }
    }

    private func labelForIndex(_ index: Int) -> String {
        let desktopNumber = monitor.spaceInfo(forIndex: index)?.desktopNumber ?? index
        let usedBy = allGroups.filter { $0.id != currentGroupID && $0.spaceIndex(on: monitor) == index }
        if let group = usedBy.first {
            return "Desktop \(desktopNumber) (used by \(group.name))"
        }
        return "Desktop \(desktopNumber)"
    }
}
