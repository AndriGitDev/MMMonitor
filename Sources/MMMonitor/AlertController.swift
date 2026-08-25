import Foundation
import UserNotifications

@MainActor
final class AlertController {
    private enum Kind: String, CaseIterable {
        case cpu
        case memory
        case disk
        case battery
        case thermal
    }

    private var consecutiveBreaches: [Kind: Int] = [:]
    private var lastDelivered: [Kind: Date] = [:]
    private var requestedAuthorization = false

    func evaluate(_ snapshot: SystemSnapshot, settings: AppSettings) {
        guard settings.alertsEnabled else {
            consecutiveBreaches.removeAll()
            return
        }

        if settings.quietHoursEnabled, isQuietHour(settings: settings) {
            consecutiveBreaches.removeAll()
            return
        }

        requestAuthorizationIfNeeded()
        let requiredSamples = max(2, Int(ceil(10 / settings.refreshInterval)))

        evaluate(
            .cpu,
            breached: snapshot.cpuUsage >= settings.cpuAlertThreshold,
            requiredSamples: requiredSamples,
            title: "High CPU Usage",
            body: "CPU usage has remained above \(percent(settings.cpuAlertThreshold)) for about 10 seconds."
        )
        evaluate(
            .memory,
            breached: snapshot.memoryUsage >= settings.memoryAlertThreshold,
            requiredSamples: requiredSamples,
            title: "High Memory Usage",
            body: "Memory usage has remained above \(percent(settings.memoryAlertThreshold)) for about 10 seconds."
        )
        evaluate(
            .disk,
            breached: snapshot.diskUsage >= settings.diskAlertThreshold,
            requiredSamples: requiredSamples,
            title: "Startup Disk Nearly Full",
            body: "Startup disk usage is above \(percent(settings.diskAlertThreshold))."
        )
        evaluate(
            .battery,
            breached: snapshot.battery.isPresent
                && !snapshot.battery.isCharging
                && !snapshot.battery.isOnACPower
                && snapshot.battery.percentage <= settings.batteryAlertThreshold,
            requiredSamples: requiredSamples,
            title: "Low Battery",
            body: "Battery level is below \(percent(settings.batteryAlertThreshold))."
        )
        evaluate(
            .thermal,
            breached: snapshot.thermalLevel == .serious || snapshot.thermalLevel == .critical,
            requiredSamples: requiredSamples,
            title: "Elevated Thermal Pressure",
            body: "macOS reports \(snapshot.thermalLevel.title.lowercased()) thermal pressure."
        )
    }

    private func evaluate(
        _ kind: Kind,
        breached: Bool,
        requiredSamples: Int,
        title: String,
        body: String
    ) {
        guard breached else {
            consecutiveBreaches[kind] = 0
            return
        }

        let count = consecutiveBreaches[kind, default: 0] + 1
        consecutiveBreaches[kind] = count
        guard count >= requiredSamples else { return }

        let now = Date()
        if let lastDelivered = lastDelivered[kind],
           now.timeIntervalSince(lastDelivered) < 15 * 60 {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "MMMonitor: \(title)"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "local.mmmonitor.\(kind.rawValue).\(Int(now.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        self.lastDelivered[kind] = now
    }

    private func requestAuthorizationIfNeeded() {
        guard !requestedAuthorization else { return }
        requestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func isQuietHour(settings: AppSettings) -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        let start = settings.quietHoursStart
        let end = settings.quietHoursEnd
        if start == end { return true }
        if start < end { return hour >= start && hour < end }
        return hour >= start || hour < end
    }
}
