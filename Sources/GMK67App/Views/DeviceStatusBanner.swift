import SwiftUI

struct DeviceStatusBanner: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.deviceStatusTitle)
                    .font(.headline)
                Text(model.deviceStatusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if model.deviceStatusKind == .permissionNeeded {
                CommandButton("Permission", systemImage: "lock.shield") {
                    model.requestInputMonitoringPermission()
                }
                CommandButton("Settings", systemImage: "gearshape") {
                    model.openInputMonitoringSettings()
                }
            }
            CommandButton("Refresh", systemImage: "arrow.clockwise") {
                model.refreshDeviceStatus()
            }
        }
        .padding(14)
        .background(tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch model.deviceStatusKind {
        case .checking:
            return "clock"
        case .ready:
            return "checkmark.seal.fill"
        case .permissionNeeded:
            return "lock.trianglebadge.exclamationmark"
        case .disconnected:
            return "cable.connector.slash"
        case .partial:
            return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch model.deviceStatusKind {
        case .checking:
            return .accentColor
        case .ready:
            return .green
        case .permissionNeeded:
            return .orange
        case .disconnected:
            return .red
        case .partial:
            return .yellow
        }
    }
}
