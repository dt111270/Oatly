import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: TaskStore
    @Binding var selection: SidebarSelection?

    private let textGrey = Color(red: 56/255.0, green: 59/255.0, blue: 63/255.0)
    private let brandBlue = Color(red: 48/255, green: 95/255, blue: 188/255)

    var roles: [String] {
        Array(Set(store.tasks.map { $0.role })).sorted()
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SmartFilter.allCases, id: \.self) { filter in
                    let isSelected = selection == .smart(filter)
                    Text(filter.label)
                        .tag(SidebarSelection.smart(filter))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? .white : textGrey)
                        .listRowBackground(isSelected ? brandBlue : Color.clear)
                }

                let recurringSelected = selection == .recurring
                Text("🔁 Recurring")
                    .tag(SidebarSelection.recurring)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(recurringSelected ? .white : textGrey)
                    .listRowBackground(recurringSelected ? brandBlue : Color.clear)
            }

            Section("Roles") {
                ForEach(roles, id: \.self) { role in
                    let isSelected = selection == .role(role)
                    Text(role)
                        .tag(SidebarSelection.role(role))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? .white : textGrey)
                        .listRowBackground(isSelected ? brandBlue : Color.clear)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(red: 235/255, green: 236/255, blue: 237/255))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(maintenanceLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Toggle(isOn: $store.iCloudSyncOverride) {
                    Label(
                        store.iCloudSyncEnabled ? "iCloud sync on" : "iCloud sync off",
                        systemImage: store.iCloudSyncEnabled ? "icloud.fill" : "icloud.slash"
                    )
                    .font(.system(size: 11))
                    .foregroundColor(store.iCloudSyncEnabled ? .blue : .secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(ProcessInfo.processInfo.hostName == "MMUtil.local")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var maintenanceLabel: String {
        if !store.iCloudSyncEnabled { return "Maintenance: off" }
        guard let date = store.lastMaintenanceRun else { return "Maintenance: pending…" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_GB")
        return "Maintenance: \(f.string(from: date))"
    }
}
