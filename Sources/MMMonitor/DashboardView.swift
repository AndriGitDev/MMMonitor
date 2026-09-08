import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var dnsCacheController: DNSCacheController
    let openSettings: @MainActor () -> Void

    private let blue = Color(red: 0.20, green: 0.55, blue: 0.95)
    private let purple = Color(red: 0.62, green: 0.38, blue: 0.92)
    private let orange = Color(red: 0.96, green: 0.55, blue: 0.18)
    private let green = Color(red: 0.20, green: 0.72, blue: 0.48)

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: settings.dashboardDensity == .compact ? 8 : 12) {
                    ForEach(settings.moduleOrder) { module in
                        moduleView(module)
                    }
                }
                .padding(settings.dashboardDensity == .compact ? 10 : 14)
            }

            footer
        }
        .frame(
            width: settings.dashboardDensity == .compact ? 320 : 348,
            height: settings.dashboardDensity == .compact ? 540 : 600
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Couldn’t Flush DNS Cache", isPresented: Binding(
            get: { dnsCacheController.errorMessage != nil },
            set: { if !$0 { dnsCacheController.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { dnsCacheController.errorMessage = nil }
        } message: {
            Text(dnsCacheController.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(blue)

            VStack(alignment: .leading, spacing: 1) {
                Text("MMMonitor")
                    .font(.headline)
                Text("M-series Mac Monitor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(green)
                .frame(width: 7, height: 7)
                .accessibilityLabel("Monitoring active")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.bar)
    }

    @ViewBuilder
    private func moduleView(_ module: MonitorModule) -> some View {
        if settings.isVisible(module) {
            switch module {
            case .cpu:
                CPUCard(
                    usage: monitor.snapshot.cpuUsage,
                    perCoreUsage: monitor.snapshot.perCoreUsage,
                    history: monitor.cpuHistory,
                    historyTitle: settings.historyRange.title,
                    color: blue
                )
            case .memory:
                MetricCard(
                    icon: "memorychip",
                    title: "Memory",
                    value: MetricFormatting.percentage(monitor.snapshot.memoryUsage),
                    detail: memoryDetail,
                    progress: monitor.snapshot.memoryUsage,
                    history: monitor.memoryHistory,
                    color: purple
                )
            case .network:
                NetworkCard(
                    downloadRate: monitor.snapshot.downloadRate,
                    uploadRate: monitor.snapshot.uploadRate,
                    interfaces: monitor.snapshot.networkInterfaces,
                    selectedInterface: $settings.selectedNetworkInterface,
                    downloadHistory: monitor.downloadHistory,
                    uploadHistory: monitor.uploadHistory,
                    interfaceDownloadHistory: monitor.interfaceDownloadHistory,
                    interfaceUploadHistory: monitor.interfaceUploadHistory,
                    dnsCacheController: dnsCacheController,
                    color: green
                )
            case .disk:
                DiskCard(
                    volumes: monitor.snapshot.volumes,
                    fallbackUsed: monitor.snapshot.diskUsed,
                    fallbackTotal: monitor.snapshot.diskTotal,
                    color: orange
                )
            case .battery:
                if monitor.snapshot.battery.isPresent {
                    BatteryCard(battery: monitor.snapshot.battery, color: green)
                } else {
                    UnavailableCard(
                        icon: "battery.0percent",
                        title: "Battery",
                        detail: "No internal battery is available on this Mac.",
                        color: green
                    )
                }
            case .processes:
                ProcessCard(
                    processes: monitor.snapshot.topProcesses,
                    sort: $settings.processSort,
                    isCollecting: monitor.cpuHistory.count < 2,
                    color: blue
                )
            case .system:
                SystemCard(
                    thermalLevel: monitor.snapshot.thermalLevel,
                    uptime: monitor.snapshot.systemUptime,
                    loadAverages: monitor.snapshot.loadAverages,
                    color: orange
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(refreshDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                monitor.refresh(forceSlowMetrics: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")

            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Open settings")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var refreshDescription: String {
        settings.refreshInterval == 1
            ? "Updated every second"
            : "Updated every \(Int(settings.refreshInterval)) seconds"
    }

    private var memoryDetail: String {
        let main = "\(MetricFormatting.byteCount(monitor.snapshot.memoryUsed)) of \(MetricFormatting.byteCount(monitor.snapshot.memoryTotal))"
        guard monitor.snapshot.swapUsed > 0 else { return "\(main) • no swap used" }
        return "\(main) • \(MetricFormatting.byteCount(monitor.snapshot.swapUsed)) swap"
    }

}

private struct UnavailableCard: View {
    let icon: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct CPUCard: View {
    let usage: Double
    let perCoreUsage: [Double]
    let history: [Double]
    let historyTitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("CPU", systemImage: "cpu")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Text(MetricFormatting.percentage(usage))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }

            Sparkline(values: history, color: color, fixedRange: 0...1)
                .frame(height: 30)

            if !perCoreUsage.isEmpty {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(perCoreUsage.enumerated()), id: \.offset) { _, coreUsage in
                        GeometryReader { geometry in
                            ZStack(alignment: .bottom) {
                                Capsule().fill(color.opacity(0.12))
                                Capsule()
                                    .fill(color.opacity(0.82))
                                    .frame(height: max(2, geometry.size.height * coreUsage))
                            }
                        }
                    }
                }
                .frame(height: 22)
                .accessibilityLabel("\(perCoreUsage.count) processor cores")
                .accessibilityValue(perCoreUsage.enumerated().map {
                    "Core \($0.offset + 1), \(MetricFormatting.percentage($0.element))"
                }.joined(separator: ", "))
            }

            HStack {
                Text("\(perCoreUsage.count) cores • \(historyTitle) history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let progress: Double
    let history: [Double]
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Text(value)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }

            if history.count > 1 {
                Sparkline(values: history, color: color, fixedRange: 0...1)
                    .frame(height: 34)
            } else {
                ProgressView(value: min(1, max(0, progress)))
                    .tint(color)
            }

            HStack {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct NetworkCard: View {
    let downloadRate: Double
    let uploadRate: Double
    let interfaces: [NetworkInterfaceSnapshot]
    @Binding var selectedInterface: String
    let downloadHistory: [Double]
    let uploadHistory: [Double]
    let interfaceDownloadHistory: [String: [Double]]
    let interfaceUploadHistory: [String: [Double]]
    @ObservedObject var dnsCacheController: DNSCacheController
    let color: Color

    private var selected: NetworkInterfaceSnapshot? {
        interfaces.first { $0.name == selectedInterface }
    }

    private var visibleDownloadRate: Double { selected?.downloadRate ?? downloadRate }
    private var visibleUploadRate: Double { selected?.uploadRate ?? uploadRate }
    private var visibleDownloadHistory: [Double] {
        selected.flatMap { interfaceDownloadHistory[$0.name] } ?? downloadHistory
    }
    private var visibleUploadHistory: [Double] {
        selected.flatMap { interfaceUploadHistory[$0.name] } ?? uploadHistory
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Network", systemImage: "network")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Button(action: dnsCacheController.flush) {
                    switch dnsCacheController.status {
                    case .idle:
                        Label("Flush DNS", systemImage: "arrow.clockwise")
                    case .flushing:
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Flushing…")
                        }
                    case .succeeded:
                        Label("Flushed", systemImage: "checkmark.circle.fill")
                    }
                }
                .controlSize(.mini)
                .disabled(dnsCacheController.status == .flushing)
                .help("Clear the macOS DNS cache (administrator approval required)")
                if !interfaces.isEmpty {
                    Picker("Network interface", selection: $selectedInterface) {
                        Text("All").tag("all")
                        ForEach(interfaces) { interface in
                            Text(interface.name).tag(interface.name)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(width: 72)
                }
            }

            if downloadHistory.count < 2 {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Collecting network activity…")
                    Spacer()
                }
                .frame(height: 38)
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if interfaces.isEmpty {
                HStack {
                    Image(systemName: "network.slash")
                    Text("No active Ethernet or Wi-Fi interface")
                    Spacer()
                }
                .frame(height: 38)
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ZStack {
                    Sparkline(values: visibleDownloadHistory, color: color)
                    Sparkline(values: visibleUploadHistory, color: .cyan)
                }
                .frame(height: 38)

                HStack {
                    Label(MetricFormatting.bytesPerSecond(visibleDownloadRate), systemImage: "arrow.down")
                    Spacer()
                    Label(MetricFormatting.bytesPerSecond(visibleUploadRate), systemImage: "arrow.up")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .onChange(of: interfaces.map(\.name)) { names in
            if selectedInterface != "all", !names.contains(selectedInterface) {
                selectedInterface = "all"
            }
        }
    }
}

private struct DiskCard: View {
    let volumes: [DiskVolumeSnapshot]
    let fallbackUsed: UInt64
    let fallbackTotal: UInt64
    let color: Color

    private var displayedVolumes: [DiskVolumeSnapshot] {
        if !volumes.isEmpty { return Array(volumes.prefix(4)) }
        return [DiskVolumeSnapshot(
            name: "Startup Disk",
            path: "/",
            used: fallbackUsed,
            total: fallbackTotal,
            isInternal: true
        )]
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Storage", systemImage: "internaldrive")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                if volumes.count > 1 {
                    Text("\(volumes.count) volumes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if volumes.isEmpty, fallbackTotal == 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Storage capacity is unavailable")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(displayedVolumes) { volume in
                    VStack(spacing: 5) {
                        HStack {
                            Text(volume.name)
                                .lineLimit(1)
                            Spacer()
                            Text("\(MetricFormatting.byteCount(volume.used)) / \(MetricFormatting.byteCount(volume.total))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)

                        ProgressView(value: volume.usage)
                            .tint(volume.usage > 0.9 ? .red : color)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

private struct BatteryCard: View {
    let battery: BatterySnapshot
    let color: Color

    var detail: String {
        if battery.isCharging { return "Charging" }
        if battery.isOnACPower { return "Connected to power" }
        if let remaining = battery.timeRemaining {
            return "About \(MetricFormatting.duration(remaining)) remaining"
        }
        return "Using battery power"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Battery", systemImage: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Text(MetricFormatting.percentage(battery.percentage))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }

            ProgressView(value: battery.percentage)
                .tint(color)

            HStack {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if battery.cycleCount != nil || battery.healthPercentage != nil {
                Divider()
                HStack {
                    if let health = battery.healthPercentage {
                        Label("\(MetricFormatting.percentage(health)) health", systemImage: "heart.text.square")
                    }
                    Spacer()
                    if let cycles = battery.cycleCount {
                        Text("\(cycles) cycles")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct ProcessCard: View {
    let processes: [ProcessSnapshot]
    @Binding var sort: ProcessSort
    let isCollecting: Bool
    let color: Color
    @State private var isExpanded = false

    private var displayedProcesses: [ProcessSnapshot] {
        let sorted: [ProcessSnapshot]
        switch sort {
        case .cpu:
            sorted = processes.sorted {
                if abs($0.cpuUsage - $1.cpuUsage) > 0.001 {
                    return $0.cpuUsage > $1.cpuUsage
                }
                return $0.memoryBytes > $1.memoryBytes
            }
        case .memory:
            sorted = processes.sorted {
                if $0.memoryBytes != $1.memoryBytes {
                    return $0.memoryBytes > $1.memoryBytes
                }
                return $0.cpuUsage > $1.cpuUsage
            }
        }
        return Array(sorted.prefix(isExpanded ? 12 : 5))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Top Processes", systemImage: "list.number")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Picker("Sort processes", selection: $sort) {
                    ForEach(ProcessSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 92)
            }

            if processes.isEmpty {
                HStack {
                    if isCollecting {
                        ProgressView()
                            .controlSize(.small)
                        Text("Collecting process activity…")
                    } else {
                        Image(systemName: "lock.shield")
                        Text("Process activity is unavailable")
                    }
                    Spacer()
                }
                .frame(height: 34)
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(displayedProcesses) { process in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(process.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("PID \(process.pid)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer(minLength: 8)

                        Text(MetricFormatting.byteCount(process.memoryBytes))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 52, alignment: .trailing)

                        Text("\(Int((process.cpuUsage * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                    .font(.caption)
                }

                if processes.count > 5 {
                    Button(isExpanded ? "Show Less" : "Show More") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isExpanded.toggle()
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

private struct SystemCard: View {
    let thermalLevel: ThermalLevel
    let uptime: TimeInterval
    let loadAverages: [Double]
    let color: Color

    private var thermalColor: Color {
        switch thermalLevel {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("System", systemImage: "desktopcomputer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
            }

            HStack(spacing: 16) {
                SystemValue(
                    label: "Thermal",
                    value: thermalLevel.title,
                    indicator: thermalColor
                )
                Divider()
                SystemValue(
                    label: "Uptime",
                    value: MetricFormatting.uptime(uptime)
                )
                Divider()
                SystemValue(
                    label: "Load (1m)",
                    value: String(format: "%.2f", loadAverages.first ?? 0)
                )
            }
            .frame(height: 34)

            HStack {
                Text("Load averages")
                Spacer()
                Text(loadAverages.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct SystemValue: View {
    let label: String
    let value: String
    var indicator: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                if let indicator {
                    Circle().fill(indicator).frame(width: 6, height: 6)
                }
                Text(value)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
