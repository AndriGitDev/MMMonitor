import AppKit
import SwiftUI

@MainActor
enum DevelopmentScreenshotExporter {
    private enum ExportError: LocalizedError {
        case couldNotRender(String)

        var errorDescription: String? {
            switch self {
            case .couldNotRender(let name):
                "Could not render \(name)."
            }
        }
    }

    static func export(to directoryPath: String) throws {
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let domain = "local.mmmonitor.screenshot"
        let defaults = UserDefaults(suiteName: domain) ?? .standard
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }

        let settings = AppSettings(defaults: defaults)
        settings.menuBarShowsIcon = true
        settings.menuBarShowsGraph = true
        settings.applyMenuBarPreset(.balanced)

        let snapshot = demoSnapshot()
        let monitor = SystemMonitor(
            settings: settings,
            previewSnapshot: snapshot,
            cpuHistory: history(base: 0.38, amplitude: 0.22, phase: 0),
            memoryHistory: history(base: 0.61, amplitude: 0.04, phase: 0.9),
            downloadHistory: rateHistory(base: 1_600_000, amplitude: 1_100_000, phase: 0.4),
            uploadHistory: rateHistory(base: 280_000, amplitude: 190_000, phase: 1.3)
        )

        let dashboard = DashboardView(
            monitor: monitor,
            settings: settings,
            openSettings: {}
        )
        .environment(\.colorScheme, .dark)

        let menuBarSettings = SettingsView(
            settings: settings,
            snapshotProvider: { snapshot },
            initialTab: .menuBar
        )
        .frame(width: 590, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)

        try render(
            dashboard,
            named: "dashboard-dark",
            size: NSSize(width: 348, height: 600),
            appearance: .darkAqua,
            in: directory
        )
        try render(
            menuBarSettings,
            named: "menu-bar-settings",
            size: NSSize(width: 590, height: 720),
            appearance: .aqua,
            in: directory
        )
        print("Exported release screenshots to \(directory.path)")
    }

    private static func render<Content: View>(
        _ content: Content,
        named name: String,
        size: NSSize,
        appearance: NSAppearance.Name,
        in directory: URL
    ) throws {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))

        let scale = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ExportError.couldNotRender(name)
        }
        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        window.orderOut(nil)
        window.close()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.couldNotRender(name)
        }
        try pngData.write(
            to: directory.appendingPathComponent("\(name).png"),
            options: .atomic
        )
    }

    private static func history(
        base: Double,
        amplitude: Double,
        phase: Double
    ) -> [Double] {
        (0..<60).map { index in
            let wave = sin(Double(index) * 0.24 + phase)
            let secondary = sin(Double(index) * 0.61 + phase) * 0.28
            return min(1, max(0, base + amplitude * (wave + secondary)))
        }
    }

    private static func rateHistory(
        base: Double,
        amplitude: Double,
        phase: Double
    ) -> [Double] {
        history(base: 0.48, amplitude: 0.34, phase: phase).map {
            max(0, base + amplitude * (($0 - 0.48) / 0.34))
        }
    }

    private static func demoSnapshot() -> SystemSnapshot {
        let gibibyte = UInt64(1_073_741_824)
        return SystemSnapshot(
            cpuUsage: 0.42,
            perCoreUsage: [0.62, 0.48, 0.53, 0.39, 0.44, 0.31, 0.28, 0.22, 0.18, 0.16],
            memoryUsed: 10 * gibibyte,
            memoryTotal: 16 * gibibyte,
            swapUsed: 384 * 1_048_576,
            swapTotal: 4 * gibibyte,
            diskUsed: 348 * gibibyte,
            diskTotal: 494 * gibibyte,
            volumes: [
                DiskVolumeSnapshot(
                    name: "Macintosh HD",
                    path: "/",
                    used: 348 * gibibyte,
                    total: 494 * gibibyte,
                    isInternal: true
                )
            ],
            downloadRate: 1_800_000,
            uploadRate: 320_000,
            networkInterfaces: [
                NetworkInterfaceSnapshot(
                    name: "en0",
                    downloadRate: 1_800_000,
                    uploadRate: 320_000
                )
            ],
            battery: BatterySnapshot(
                isPresent: true,
                percentage: 0.78,
                isCharging: false,
                isOnACPower: false,
                timeRemaining: 5.4 * 3_600,
                cycleCount: 126,
                healthPercentage: 0.96
            ),
            topProcesses: [
                ProcessSnapshot(pid: 421, name: "Xcode", cpuUsage: 0.18, memoryBytes: 1_900_000_000),
                ProcessSnapshot(pid: 892, name: "Safari", cpuUsage: 0.11, memoryBytes: 940_000_000),
                ProcessSnapshot(pid: 1_204, name: "MMMonitor", cpuUsage: 0.01, memoryBytes: 36_000_000)
            ],
            thermalLevel: .nominal,
            systemUptime: 3 * 86_400 + 7 * 3_600,
            loadAverages: [2.18, 2.04, 1.92],
            sampledAt: Date(timeIntervalSince1970: 1_787_650_000)
        )
    }
}
