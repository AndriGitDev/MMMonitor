import Foundation

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot.empty
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var downloadHistory: [Double] = []
    @Published private(set) var uploadHistory: [Double] = []
    @Published private(set) var interfaceDownloadHistory: [String: [Double]] = [:]
    @Published private(set) var interfaceUploadHistory: [String: [Double]] = [:]

    private let sampler = SystemSampler()
    private let alertController = AlertController()
    private let settings: AppSettings
    private var timer: Timer?
    private var refreshInterval: TimeInterval

    init(settings: AppSettings) {
        self.settings = settings
        self.refreshInterval = settings.refreshInterval
        settings.refreshIntervalDidChange = { [weak self] interval in
            self?.setRefreshInterval(interval)
        }
        settings.historyRangeDidChange = { [weak self] in
            self?.updateHistoryRange()
        }
        refresh()
        scheduleTimer()
    }

    init(
        settings: AppSettings,
        previewSnapshot: SystemSnapshot,
        cpuHistory: [Double],
        memoryHistory: [Double],
        downloadHistory: [Double],
        uploadHistory: [Double]
    ) {
        self.settings = settings
        refreshInterval = settings.refreshInterval
        snapshot = previewSnapshot
        self.cpuHistory = cpuHistory
        self.memoryHistory = memoryHistory
        self.downloadHistory = downloadHistory
        self.uploadHistory = uploadHistory
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        guard interval != refreshInterval else { return }
        refreshInterval = interval
        trimHistories()
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh(forceSlowMetrics: Bool = false) {
        snapshot = sampler.sample(forceSlowMetrics: forceSlowMetrics)
        alertController.evaluate(snapshot, settings: settings)
        append(snapshot.cpuUsage, to: &cpuHistory)
        append(snapshot.memoryUsage, to: &memoryHistory)
        append(snapshot.downloadRate, to: &downloadHistory)
        append(snapshot.uploadRate, to: &uploadHistory)
        for interface in snapshot.networkInterfaces {
            append(interface.downloadRate, to: &interfaceDownloadHistory[interface.name, default: []])
            append(interface.uploadRate, to: &interfaceUploadHistory[interface.name, default: []])
        }
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        let historyLimit = max(2, Int(Double(settings.historyRange.seconds) / refreshInterval))
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    private func trimHistories() {
        let limit = max(2, Int(Double(settings.historyRange.seconds) / refreshInterval))
        cpuHistory = Array(cpuHistory.suffix(limit))
        memoryHistory = Array(memoryHistory.suffix(limit))
        downloadHistory = Array(downloadHistory.suffix(limit))
        uploadHistory = Array(uploadHistory.suffix(limit))
        interfaceDownloadHistory = interfaceDownloadHistory.mapValues { Array($0.suffix(limit)) }
        interfaceUploadHistory = interfaceUploadHistory.mapValues { Array($0.suffix(limit)) }
    }

    func updateHistoryRange() {
        trimHistories()
    }
}
