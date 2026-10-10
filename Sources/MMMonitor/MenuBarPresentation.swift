import AppKit
import SwiftUI

@MainActor
enum MenuBarPresentation {
    static func text(
        snapshot: SystemSnapshot,
        components: Set<MenuBarComponent>,
        order: [MenuBarComponent]
    ) -> String {
        order.compactMap { component in
            guard components.contains(component) else { return nil }
            return switch component {
            case .cpu:
                "C\(MetricFormatting.compactPercentage(snapshot.cpuUsage))"
            case .memory:
                "M\(MetricFormatting.compactPercentage(snapshot.memoryUsage))"
            case .disk:
                "D\(MetricFormatting.compactPercentage(snapshot.diskUsage))"
            case .download:
                "↓\(MetricFormatting.compactRate(snapshot.downloadRate))"
            case .upload:
                "↑\(MetricFormatting.compactRate(snapshot.uploadRate))"
            case .battery:
                batteryText(snapshot.battery)
            case .thermal:
                "T \(thermalAbbreviation(snapshot.thermalLevel))"
            }
        }.joined(separator: "  ")
    }

    static func accessibilityText(
        snapshot: SystemSnapshot,
        components: Set<MenuBarComponent>,
        order: [MenuBarComponent]
    ) -> String {
        let metrics = order.compactMap { component -> String? in
            guard components.contains(component) else { return nil }
            return switch component {
            case .cpu:
                "CPU \(MetricFormatting.percentage(snapshot.cpuUsage))"
            case .memory:
                "memory \(MetricFormatting.percentage(snapshot.memoryUsage))"
            case .disk:
                "disk \(MetricFormatting.percentage(snapshot.diskUsage))"
            case .download:
                "download \(MetricFormatting.bytesPerSecond(snapshot.downloadRate))"
            case .upload:
                "upload \(MetricFormatting.bytesPerSecond(snapshot.uploadRate))"
            case .battery:
                snapshot.battery.isPresent
                    ? "battery \(MetricFormatting.percentage(snapshot.battery.percentage))\(snapshot.battery.isCharging ? ", charging" : "")"
                    : "battery unavailable"
            case .thermal:
                "thermal state \(snapshot.thermalLevel.title)"
            }
        }
        return "MMMonitor, " + metrics.joined(separator: ", ")
    }

    private static func thermalAbbreviation(_ level: ThermalLevel) -> String {
        switch level {
        case .nominal: "OK  "
        case .fair: "Fair"
        case .serious: "Hot "
        case .critical: "Crit"
        }
    }

    private static func batteryText(_ battery: BatterySnapshot) -> String {
        guard battery.isPresent else { return "B  --" }
        let percentage = MetricFormatting.compactPercentage(battery.percentage)
        guard battery.isCharging else { return "B\(percentage)" }
        return "B+\(percentage.dropFirst())"
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitorState: MenuBarMonitorState
    @ObservedObject var settings: AppSettings
    @ObservedObject var awakeSessionController: AwakeSessionController

    init(
        monitor: SystemMonitor,
        settings: AppSettings,
        awakeSessionController: AwakeSessionController
    ) {
        monitorState = monitor.menuBarState
        self.settings = settings
        self.awakeSessionController = awakeSessionController
    }

    private var metricText: some View {
        Text(MenuBarPresentation.text(
            snapshot: monitorState.presentation.snapshot,
            components: settings.menuBarComponents,
            order: settings.menuBarComponentOrder
        ))
        .font(.system(size: 12, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    var body: some View {
        HStack(spacing: 4) {
            if awakeSessionController.isActive {
                Label(awakeSessionController.remainingText, systemImage: "cup.and.saucer.fill")
                    .font(.system(size: 12, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if settings.menuBarShowsGraph {
                MenuBarSparkline(values: monitorState.presentation.cpuHistory)
            }
            if settings.menuBarShowsIcon {
                Image(systemName: "gauge.with.dots.needle.50percent")
            }
            metricText
        }
        .help("MMMonitor — click for details")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let metrics = MenuBarPresentation.accessibilityText(
            snapshot: monitorState.presentation.snapshot,
            components: settings.menuBarComponents,
            order: settings.menuBarComponentOrder
        )
        guard awakeSessionController.isActive else { return metrics }
        return "MMMonitor, Keep Awake active, \(awakeSessionController.remainingText), " +
            metrics.replacingOccurrences(of: "MMMonitor, ", with: "")
    }
}

private struct MenuBarSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            let points = normalizedPoints(in: geometry.size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .frame(width: 28, height: 12)
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let normalized = min(1, max(0, value))
            let y = size.height * (1 - CGFloat(normalized))
            return CGPoint(x: x, y: y)
        }
    }
}
