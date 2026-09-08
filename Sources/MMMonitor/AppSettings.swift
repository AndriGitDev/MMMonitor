import Foundation
import ServiceManagement

enum MonitorModule: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case network
    case disk
    case battery
    case processes
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        case .disk: "Disk"
        case .battery: "Battery"
        case .processes: "Top Processes"
        case .system: "System"
        }
    }
}

enum MenuBarComponent: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case disk
    case download
    case upload
    case battery
    case thermal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .download: "Download"
        case .upload: "Upload"
        case .battery: "Battery"
        case .thermal: "Thermal State"
        }
    }
}

enum MenuBarPreset: String, CaseIterable, Identifiable, Sendable {
    case compact
    case balanced
    case network
    case full

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var components: Set<MenuBarComponent> {
        switch self {
        case .compact: [.cpu]
        case .balanced: [.cpu, .memory, .download, .battery]
        case .network: [.download, .upload]
        case .full: Set(MenuBarComponent.allCases)
        }
    }
}

enum ProcessSort: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum DashboardDensity: String, CaseIterable, Identifiable, Sendable {
    case compact
    case comfortable

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum HistoryRange: Int, CaseIterable, Identifiable, Sendable {
    case oneMinute = 60
    case fifteenMinutes = 900
    case oneHour = 3_600
    case oneDay = 86_400

    var id: Int { rawValue }
    var seconds: Int { rawValue }

    var title: String {
        switch self {
        case .oneMinute: "1 minute"
        case .fifteenMinutes: "15 minutes"
        case .oneHour: "1 hour"
        case .oneDay: "1 day"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var refreshInterval: Double {
        didSet {
            defaults.set(refreshInterval, forKey: Keys.refreshInterval)
            refreshIntervalDidChange?(refreshInterval)
        }
    }

    @Published private(set) var menuBarComponents: Set<MenuBarComponent> {
        didSet {
            defaults.set(menuBarComponents.map(\.rawValue).sorted(), forKey: Keys.menuBarComponents)
        }
    }

    @Published private(set) var menuBarComponentOrder: [MenuBarComponent] {
        didSet { defaults.set(menuBarComponentOrder.map(\.rawValue), forKey: Keys.menuBarComponentOrder) }
    }

    @Published var menuBarShowsIcon: Bool {
        didSet { defaults.set(menuBarShowsIcon, forKey: Keys.menuBarShowsIcon) }
    }

    @Published var menuBarShowsGraph: Bool {
        didSet { defaults.set(menuBarShowsGraph, forKey: Keys.menuBarShowsGraph) }
    }

    @Published private(set) var visibleModules: Set<MonitorModule> {
        didSet {
            defaults.set(visibleModules.map(\.rawValue).sorted(), forKey: Keys.visibleModules)
        }
    }

    @Published private(set) var moduleOrder: [MonitorModule] {
        didSet { defaults.set(moduleOrder.map(\.rawValue), forKey: Keys.moduleOrder) }
    }

    @Published private(set) var launchAtLoginStatus: SMAppService.Status
    @Published var processSort: ProcessSort {
        didSet { defaults.set(processSort.rawValue, forKey: Keys.processSort) }
    }
    @Published var selectedNetworkInterface: String {
        didSet { defaults.set(selectedNetworkInterface, forKey: Keys.selectedNetworkInterface) }
    }
    @Published var dashboardDensity: DashboardDensity {
        didSet { defaults.set(dashboardDensity.rawValue, forKey: Keys.dashboardDensity) }
    }
    @Published var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) }
    }
    @Published var cpuAlertThreshold: Double {
        didSet { defaults.set(cpuAlertThreshold, forKey: Keys.cpuAlertThreshold) }
    }
    @Published var memoryAlertThreshold: Double {
        didSet { defaults.set(memoryAlertThreshold, forKey: Keys.memoryAlertThreshold) }
    }
    @Published var diskAlertThreshold: Double {
        didSet { defaults.set(diskAlertThreshold, forKey: Keys.diskAlertThreshold) }
    }
    @Published var batteryAlertThreshold: Double {
        didSet { defaults.set(batteryAlertThreshold, forKey: Keys.batteryAlertThreshold) }
    }
    @Published var historyRange: HistoryRange {
        didSet {
            defaults.set(historyRange.rawValue, forKey: Keys.historyRange)
            historyRangeDidChange?()
        }
    }
    @Published var persistedHistoryEnabled: Bool {
        didSet {
            defaults.set(persistedHistoryEnabled, forKey: Keys.persistedHistoryEnabled)
            persistedHistoryEnabledDidChange?(persistedHistoryEnabled)
        }
    }
    @Published private(set) var oneDayHistorySampleCount = 0
    @Published var quietHoursEnabled: Bool {
        didSet { defaults.set(quietHoursEnabled, forKey: Keys.quietHoursEnabled) }
    }
    @Published var quietHoursStart: Int {
        didSet { defaults.set(quietHoursStart, forKey: Keys.quietHoursStart) }
    }
    @Published var quietHoursEnd: Int {
        didSet { defaults.set(quietHoursEnd, forKey: Keys.quietHoursEnd) }
    }
    @Published var errorMessage: String?

    var refreshIntervalDidChange: (@MainActor (Double) -> Void)?
    var historyRangeDidChange: (@MainActor () -> Void)?
    var persistedHistoryEnabledDidChange: (@MainActor (Bool) -> Void)?
    var clearHistoryRequested: (@MainActor () -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedInterval = defaults.double(forKey: Keys.refreshInterval)
        refreshInterval = [1.0, 2.0, 5.0].contains(savedInterval) ? savedInterval : 1.0

        if let savedComponents = defaults.stringArray(forKey: Keys.menuBarComponents) {
            let parsed = Set(savedComponents.compactMap(MenuBarComponent.init(rawValue:)))
            let validComponents = parsed.isEmpty ? MenuBarPreset.balanced.components : parsed
            if defaults.integer(forKey: Keys.menuBarLayoutVersion) < 1,
               validComponents == MenuBarPreset.compact.components {
                menuBarComponents = MenuBarPreset.balanced.components
            } else {
                menuBarComponents = validComponents
            }
        } else {
            let migrated = Self.migratedMenuBarComponents(defaults)
            menuBarComponents = migrated == MenuBarPreset.compact.components
                ? MenuBarPreset.balanced.components
                : migrated
        }
        defaults.set(1, forKey: Keys.menuBarLayoutVersion)

        let rawMenuBarOrder = defaults.stringArray(forKey: Keys.menuBarComponentOrder)?
            .compactMap(MenuBarComponent.init(rawValue:)) ?? []
        var seenMenuBarComponents: Set<MenuBarComponent> = []
        let savedMenuBarOrder = rawMenuBarOrder.filter {
            seenMenuBarComponents.insert($0).inserted
        }
        let missingMenuBarComponents = MenuBarComponent.allCases.filter {
            !savedMenuBarOrder.contains($0)
        }
        menuBarComponentOrder = savedMenuBarOrder + missingMenuBarComponents
        menuBarShowsIcon = defaults.object(forKey: Keys.menuBarShowsIcon) == nil
            ? false : defaults.bool(forKey: Keys.menuBarShowsIcon)
        menuBarShowsGraph = defaults.bool(forKey: Keys.menuBarShowsGraph)

        if let savedModules = defaults.stringArray(forKey: Keys.visibleModules) {
            let parsed = Set(savedModules.compactMap(MonitorModule.init(rawValue:)))
            visibleModules = parsed.isEmpty ? Set(MonitorModule.allCases) : parsed
        } else {
            visibleModules = Set(MonitorModule.allCases)
        }

        let savedOrder = defaults.stringArray(forKey: Keys.moduleOrder)?
            .compactMap(MonitorModule.init(rawValue:)) ?? []
        let missingModules = MonitorModule.allCases.filter { !savedOrder.contains($0) }
        moduleOrder = savedOrder + missingModules

        launchAtLoginStatus = SMAppService.mainApp.status
        processSort = ProcessSort(
            rawValue: defaults.string(forKey: Keys.processSort) ?? ""
        ) ?? .cpu
        selectedNetworkInterface = defaults.string(forKey: Keys.selectedNetworkInterface) ?? "all"
        dashboardDensity = DashboardDensity(
            rawValue: defaults.string(forKey: Keys.dashboardDensity) ?? ""
        ) ?? .comfortable
        alertsEnabled = defaults.bool(forKey: Keys.alertsEnabled)
        cpuAlertThreshold = Self.savedThreshold(
            defaults,
            key: Keys.cpuAlertThreshold,
            fallback: 0.9
        )
        memoryAlertThreshold = Self.savedThreshold(
            defaults,
            key: Keys.memoryAlertThreshold,
            fallback: 0.9
        )
        diskAlertThreshold = Self.savedThreshold(
            defaults,
            key: Keys.diskAlertThreshold,
            fallback: 0.9
        )
        batteryAlertThreshold = Self.savedThreshold(
            defaults,
            key: Keys.batteryAlertThreshold,
            fallback: 0.2
        )
        historyRange = HistoryRange(
            rawValue: defaults.integer(forKey: Keys.historyRange)
        ) ?? .oneMinute
        persistedHistoryEnabled = defaults.bool(forKey: Keys.persistedHistoryEnabled)
        quietHoursEnabled = defaults.bool(forKey: Keys.quietHoursEnabled)
        quietHoursStart = defaults.object(forKey: Keys.quietHoursStart) == nil
            ? 22 : defaults.integer(forKey: Keys.quietHoursStart)
        quietHoursEnd = defaults.object(forKey: Keys.quietHoursEnd) == nil
            ? 8 : defaults.integer(forKey: Keys.quietHoursEnd)

        defaults.set(
            menuBarComponents.map(\.rawValue).sorted(),
            forKey: Keys.menuBarComponents
        )
        defaults.set(menuBarComponentOrder.map(\.rawValue), forKey: Keys.menuBarComponentOrder)
    }

    func isVisible(_ module: MonitorModule) -> Bool {
        visibleModules.contains(module)
    }

    func setVisible(_ module: MonitorModule, _ visible: Bool) {
        if visible {
            visibleModules.insert(module)
        } else if visibleModules.count > 1 {
            visibleModules.remove(module)
        }
    }

    func moveModule(_ module: MonitorModule, by offset: Int) {
        guard let currentIndex = moduleOrder.firstIndex(of: module) else { return }
        let destination = currentIndex + offset
        guard moduleOrder.indices.contains(destination) else { return }
        moduleOrder.swapAt(currentIndex, destination)
    }

    func clearHistory() {
        clearHistoryRequested?()
    }

    func updateOneDayHistorySampleCount(_ count: Int) {
        oneDayHistorySampleCount = count
    }

    func showsInMenuBar(_ component: MenuBarComponent) -> Bool {
        menuBarComponents.contains(component)
    }

    func setMenuBarComponent(_ component: MenuBarComponent, _ visible: Bool) {
        if visible {
            menuBarComponents.insert(component)
        } else if menuBarComponents.count > 1 {
            menuBarComponents.remove(component)
        }
    }

    func applyMenuBarPreset(_ preset: MenuBarPreset) {
        menuBarComponents = preset.components
    }

    func moveMenuBarComponent(_ component: MenuBarComponent, by offset: Int) {
        guard let currentIndex = menuBarComponentOrder.firstIndex(of: component) else { return }
        let destination = currentIndex + offset
        guard menuBarComponentOrder.indices.contains(destination) else { return }
        menuBarComponentOrder.swapAt(currentIndex, destination)
    }

    func resetMenuBarComponentOrder() {
        menuBarComponentOrder = MenuBarComponent.allCases
    }

    func toggleLaunchAtLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notRegistered, .notFound:
                try SMAppService.mainApp.register()
            @unknown default:
                try SMAppService.mainApp.register()
            }
            launchAtLoginStatus = SMAppService.mainApp.status
        } catch {
            launchAtLoginStatus = SMAppService.mainApp.status
            errorMessage = "Launch at login could not be changed: \(error.localizedDescription)"
        }
    }

    var launchesAtLogin: Bool {
        launchAtLoginStatus == .enabled
    }

    var launchAtLoginNeedsApproval: Bool {
        launchAtLoginStatus == .requiresApproval
    }

    private static func savedThreshold(
        _ defaults: UserDefaults,
        key: String,
        fallback: Double
    ) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }

    private static func migratedMenuBarComponents(_ defaults: UserDefaults) -> Set<MenuBarComponent> {
        switch defaults.string(forKey: Keys.legacyMenuBarMetric) {
        case "memory": [.memory]
        case "download": [.download]
        case "upload": [.upload]
        case "battery": [.battery]
        default: MenuBarPreset.compact.components
        }
    }

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let menuBarComponents = "menuBarComponents"
        static let menuBarComponentOrder = "menuBarComponentOrder"
        static let menuBarShowsIcon = "menuBarShowsIcon"
        static let menuBarShowsGraph = "menuBarShowsGraph"
        static let legacyMenuBarMetric = "menuBarMetric"
        static let menuBarLayoutVersion = "menuBarLayoutVersion"
        static let visibleModules = "visibleModules"
        static let moduleOrder = "moduleOrder"
        static let processSort = "processSort"
        static let selectedNetworkInterface = "selectedNetworkInterface"
        static let dashboardDensity = "dashboardDensity"
        static let alertsEnabled = "alertsEnabled"
        static let cpuAlertThreshold = "cpuAlertThreshold"
        static let memoryAlertThreshold = "memoryAlertThreshold"
        static let diskAlertThreshold = "diskAlertThreshold"
        static let batteryAlertThreshold = "batteryAlertThreshold"
        static let historyRange = "historyRange"
        static let persistedHistoryEnabled = "persistedHistoryEnabled"
        static let quietHoursEnabled = "quietHoursEnabled"
        static let quietHoursStart = "quietHoursStart"
        static let quietHoursEnd = "quietHoursEnd"
    }
}
