import SwiftUI

@main
@MainActor
struct MMMonitorApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var monitor: SystemMonitor
    @StateObject private var dnsCacheController: DNSCacheController
    @StateObject private var awakeSessionController: AwakeSessionController
    private let settingsWindowController: SettingsWindowController

    init() {
        let settings = AppSettings()
        let monitor = SystemMonitor(settings: settings)
        let dnsCacheController = DNSCacheController()
        let awakeSessionController = AwakeSessionController()
        _settings = StateObject(wrappedValue: settings)
        _monitor = StateObject(wrappedValue: monitor)
        _dnsCacheController = StateObject(wrappedValue: dnsCacheController)
        _awakeSessionController = StateObject(wrappedValue: awakeSessionController)
        let settingsWindowController = SettingsWindowController(
            settings: settings,
            snapshotProvider: { [weak monitor] in monitor?.snapshot ?? .empty }
        )
        self.settingsWindowController = settingsWindowController
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.async {
                settingsWindowController.show()
            }
        }
        if let argumentIndex = CommandLine.arguments.firstIndex(of: "--export-screenshots"),
           CommandLine.arguments.indices.contains(argumentIndex + 1) {
            let outputDirectory = CommandLine.arguments[argumentIndex + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                do {
                    try DevelopmentScreenshotExporter.export(to: outputDirectory)
                } catch {
                    FileHandle.standardError.write(
                        Data("Screenshot export failed: \(error.localizedDescription)\n".utf8)
                    )
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(
                monitor: monitor,
                settings: settings,
                dnsCacheController: dnsCacheController,
                awakeSessionController: awakeSessionController,
                openSettings: settingsWindowController.show
            )
        } label: {
            MenuBarLabel(
                monitor: monitor,
                settings: settings,
                awakeSessionController: awakeSessionController
            )
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…", action: settingsWindowController.show)
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
