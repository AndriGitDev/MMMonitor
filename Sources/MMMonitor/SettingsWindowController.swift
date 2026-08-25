import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private var hasPosition = false

    init(
        settings: AppSettings,
        snapshotProvider: @escaping @MainActor () -> SystemSnapshot
    ) {
        let settingsView = SettingsView(
            settings: settings,
            snapshotProvider: snapshotProvider
        )
        let hostingController = NSHostingController(rootView: settingsView)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 590, height: 610),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MMMonitor Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 540, height: 540)
        let frameName = "MMMonitorSettingsWindow"
        hasPosition = window.setFrameUsingName(frameName)
        window.setFrameAutosaveName(frameName)
    }

    func show() {
        if !hasPosition {
            window.center()
            hasPosition = true
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
