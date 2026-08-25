import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case general
    case menuBar
    case dashboard
    case alerts
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let snapshotProvider: @MainActor () -> SystemSnapshot
    @State private var selectedTab: SettingsTab

    init(
        settings: AppSettings,
        snapshotProvider: @escaping @MainActor () -> SystemSnapshot,
        initialTab: SettingsTab = .general
    ) {
        self.settings = settings
        self.snapshotProvider = snapshotProvider
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MMMonitor Settings").font(.headline)
                    Text("Changes are saved automatically").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            TabView(selection: $selectedTab) {
                GeneralSettingsTab(settings: settings)
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsTab.general)

                MenuBarSettingsTab(settings: settings, snapshotProvider: snapshotProvider)
                    .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                    .tag(SettingsTab.menuBar)

                DashboardSettingsTab(settings: settings)
                    .tabItem { Label("Dashboard", systemImage: "rectangle.grid.1x2") }
                    .tag(SettingsTab.dashboard)

                AlertSettingsTab(settings: settings)
                    .tabItem { Label("Alerts", systemImage: "bell") }
                    .tag(SettingsTab.alerts)
            }
            .padding(.horizontal, 12)

            Divider()

            HStack {
                Button("Copy Snapshot") { exportSnapshot(copyToClipboard: true) }
                Button("Save Snapshot…") { exportSnapshot(copyToClipboard: false) }
                Spacer()
                Button("About") { showAboutPanel() }
            }
            .padding(12)
        }
        .frame(minWidth: 540, minHeight: 540)
        .alert("MMMonitor", isPresented: Binding(
            get: { settings.errorMessage != nil },
            set: { if !$0 { settings.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { settings.errorMessage = nil }
        } message: {
            Text(settings.errorMessage ?? "An unknown error occurred.")
        }
    }

    private func exportSnapshot(copyToClipboard: Bool) {
        do {
            let snapshot = snapshotProvider()
            if copyToClipboard {
                try SnapshotExporter.copy(snapshot)
            } else {
                try SnapshotExporter.save(snapshot)
            }
        } catch {
            settings.errorMessage = "The snapshot could not be exported: \(error.localizedDescription)"
        }
    }

    private func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "Development"
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "MMMonitor",
            .applicationVersion: version,
            .credits: NSAttributedString(
                string: "M-series Mac Monitor\nLocal, lightweight, and open source."
            )
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Monitoring") {
                Picker("Refresh interval", selection: $settings.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
                Picker("Live history", selection: $settings.historyRange) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.title.capitalized).tag(range)
                    }
                }
                Picker("Dashboard density", selection: $settings.dashboardDensity) {
                    ForEach(DashboardDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch MMMonitor at login", isOn: Binding(
                    get: { settings.launchesAtLogin },
                    set: { _ in settings.toggleLaunchAtLogin() }
                ))
                if settings.launchAtLoginNeedsApproval {
                    Text("Approval is required in System Settings → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct MenuBarSettingsTab: View {
    @ObservedObject var settings: AppSettings
    let snapshotProvider: @MainActor () -> SystemSnapshot
    @State private var previewSnapshot = SystemSnapshot.empty

    var body: some View {
        Form {
            Section("Preview") {
                HStack {
                    if settings.menuBarShowsGraph {
                        SettingsPreviewSparkline()
                    }
                    if settings.menuBarShowsIcon {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                    }
                    Text(MenuBarPresentation.text(
                        snapshot: previewSnapshot,
                        components: settings.menuBarComponents,
                        order: settings.menuBarComponentOrder
                    ))
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    Spacer()
                    Button("Refresh") { previewSnapshot = snapshotProvider() }
                }
                .padding(.vertical, 5)
                Text("The preview refreshes only when requested, keeping every control stable while you configure it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Presets") {
                HStack {
                    ForEach(MenuBarPreset.allCases) { preset in
                        Button {
                            settings.applyMenuBarPreset(preset)
                        } label: {
                            Label(
                                preset.title,
                                systemImage: settings.menuBarComponents == preset.components
                                    ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                }
            }

            Section("Display") {
                Toggle("Show MMMonitor icon", isOn: $settings.menuBarShowsIcon)
                Toggle("Show CPU sparkline", isOn: $settings.menuBarShowsGraph)
                Text("Metrics use fixed-width values so the menu bar does not jump as readings change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Visible Metrics") {
                ForEach(Array(settings.menuBarComponentOrder.enumerated()), id: \.element.id) { index, component in
                    HStack {
                        Toggle(component.title, isOn: Binding(
                            get: { settings.showsInMenuBar(component) },
                            set: { settings.setMenuBarComponent(component, $0) }
                        ))
                        Spacer()
                        Button { settings.moveMenuBarComponent(component, by: -1) } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .help("Move left")
                        .accessibilityLabel("Move \(component.title) left")
                        Button { settings.moveMenuBarComponent(component, by: 1) } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == settings.menuBarComponentOrder.count - 1)
                        .help("Move right")
                        .accessibilityLabel("Move \(component.title) right")
                    }
                }
                Text("At least one metric remains visible. Network values use compact K/M/G units per second.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("C CPU · M memory · D disk · ↓ download · ↑ upload · B battery · T thermal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Reset Order") { settings.resetMenuBarComponentOrder() }
                        .disabled(settings.menuBarComponentOrder == MenuBarComponent.allCases)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { previewSnapshot = snapshotProvider() }
    }
}

private struct SettingsPreviewSparkline: View {
    private let values = [0.18, 0.24, 0.2, 0.42, 0.33, 0.7, 0.48, 0.38, 0.55, 0.3]

    var body: some View {
        Sparkline(values: values, color: .primary, fixedRange: 0...1)
        .frame(width: 28, height: 12)
    }
}

private struct DashboardSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array(settings.moduleOrder.enumerated()), id: \.element.id) { index, module in
                    HStack {
                        Toggle(module.title, isOn: Binding(
                            get: { settings.isVisible(module) },
                            set: { settings.setVisible(module, $0) }
                        ))
                        Spacer()
                        Button { settings.moveModule(module, by: -1) } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(index == 0)
                        .help("Move up")
                        Button { settings.moveModule(module, by: 1) } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(index == settings.moduleOrder.count - 1)
                        .help("Move down")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
        }
    }
}

private struct AlertSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Enable sustained-threshold alerts", isOn: $settings.alertsEnabled)
                Text("Conditions must persist for about 10 seconds. Each alert has a 15-minute cooldown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Thresholds") {
                thresholdPicker("CPU", selection: $settings.cpuAlertThreshold, values: [0.8, 0.9, 0.95])
                thresholdPicker("Memory", selection: $settings.memoryAlertThreshold, values: [0.8, 0.9, 0.95])
                thresholdPicker("Disk", selection: $settings.diskAlertThreshold, values: [0.8, 0.9, 0.95])
                thresholdPicker("Battery", selection: $settings.batteryAlertThreshold, values: [0.1, 0.2, 0.3])
            }

            Section("Quiet Hours") {
                Toggle("Enable quiet hours", isOn: $settings.quietHoursEnabled)
                Picker("Start", selection: $settings.quietHoursStart) {
                    ForEach(0..<24, id: \.self) { Text(formattedHour($0)).tag($0) }
                }
                Picker("End", selection: $settings.quietHoursEnd) {
                    ForEach(0..<24, id: \.self) { Text(formattedHour($0)).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func thresholdPicker(
        _ title: String,
        selection: Binding<Double>,
        values: [Double]
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(MetricFormatting.percentage(value)).tag(value)
            }
        }
    }

    private func formattedHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
