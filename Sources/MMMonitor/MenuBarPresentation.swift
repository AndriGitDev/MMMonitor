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
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var settings: AppSettings

    private var metricText: some View {
        Text(MenuBarPresentation.text(
            snapshot: monitor.snapshot,
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
            if settings.menuBarShowsGraph {
                MenuBarSparkline(values: monitor.cpuHistory)
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
        MenuBarPresentation.accessibilityText(
            snapshot: monitor.snapshot,
            components: settings.menuBarComponents,
            order: settings.menuBarComponentOrder
        )
    }
}

private struct MenuBarSparkline: View {
    let values: [Double]

    var body: some View {
        Image(nsImage: MenuBarSparklineRenderer.image(values: Array(values.suffix(30))))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: 28, height: 12)
            .accessibilityHidden(true)
    }
}

private enum MenuBarSparklineRenderer {
    private static let size = NSSize(width: 28, height: 12)

    static func image(values: [Double]) -> NSImage {
        let image = NSImage(size: size, flipped: true) { bounds in
            let points = normalizedPoints(values: values, in: bounds.size)
            guard points.count > 1 else { return true }

            let fill = NSBezierPath()
            fill.move(to: NSPoint(x: points[0].x, y: bounds.height))
            for point in points {
                fill.line(to: point)
            }
            fill.line(to: NSPoint(x: points[points.count - 1].x, y: bounds.height))
            fill.close()
            NSColor.black.withAlphaComponent(0.22).setFill()
            fill.fill()

            let line = NSBezierPath()
            line.move(to: points[0])
            for point in points.dropFirst() {
                line.line(to: point)
            }
            line.lineWidth = 1.5
            line.lineJoinStyle = .round
            line.lineCapStyle = .round
            NSColor.black.setStroke()
            line.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func normalizedPoints(values: [Double], in size: NSSize) -> [NSPoint] {
        guard values.count > 1 else { return [] }
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let normalized = min(1, max(0, value))
            let y = size.height * (1 - CGFloat(normalized))
            return NSPoint(x: x, y: y)
        }
    }
}
