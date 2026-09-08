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
    private let persistedHistoryStore: PersistedHistoryStore?
    private var timer: Timer?
    private var refreshInterval: TimeInterval
    private var liveCPUHistory: [Double] = []
    private var liveMemoryHistory: [Double] = []
    private var liveDownloadHistory: [Double] = []
    private var liveUploadHistory: [Double] = []
    private var liveInterfaceDownloadHistory: [String: [Double]] = [:]
    private var liveInterfaceUploadHistory: [String: [Double]] = [:]
    private var minuteHistoryAccumulator = MinuteHistoryAccumulator()
    private var oneDaySamples: [MinuteHistorySample] = []
    private var historyLoadTask: Task<Void, Never>?
    private var historyPersistenceTask: Task<Void, Never>?
    private var hasLoadedPersistedHistory = false
    private var shouldPersistAfterLoad = false

    init(settings: AppSettings) {
        self.settings = settings
        let persistedHistoryStore = PersistedHistoryStore()
        self.persistedHistoryStore = persistedHistoryStore
        self.refreshInterval = settings.refreshInterval
        settings.refreshIntervalDidChange = { [weak self] interval in
            self?.setRefreshInterval(interval)
        }
        settings.historyRangeDidChange = { [weak self] in
            self?.updateHistoryRange()
        }
        settings.persistedHistoryEnabledDidChange = { [weak self] enabled in
            self?.persistenceSettingDidChange(enabled)
        }
        settings.clearHistoryRequested = { [weak self] in
            self?.clearHistory()
        }
        refresh()
        scheduleTimer()
        loadPersistedHistory(from: persistedHistoryStore)
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
        persistedHistoryStore = nil
        refreshInterval = settings.refreshInterval
        snapshot = previewSnapshot
        self.cpuHistory = cpuHistory
        self.memoryHistory = memoryHistory
        self.downloadHistory = downloadHistory
        self.uploadHistory = uploadHistory
        liveCPUHistory = cpuHistory
        liveMemoryHistory = memoryHistory
        liveDownloadHistory = downloadHistory
        liveUploadHistory = uploadHistory
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        guard interval != refreshInterval else { return }
        refreshInterval = interval
        trimLiveHistories()
        publishHistories()
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
        appendLive(snapshot.cpuUsage, to: &liveCPUHistory)
        appendLive(snapshot.memoryUsage, to: &liveMemoryHistory)
        appendLive(snapshot.downloadRate, to: &liveDownloadHistory)
        appendLive(snapshot.uploadRate, to: &liveUploadHistory)
        for interface in snapshot.networkInterfaces {
            appendLive(
                interface.downloadRate,
                to: &liveInterfaceDownloadHistory[interface.name, default: []]
            )
            appendLive(
                interface.uploadRate,
                to: &liveInterfaceUploadHistory[interface.name, default: []]
            )
        }

        if let completedSample = minuteHistoryAccumulator.add(snapshot) {
            oneDaySamples.append(completedSample)
            oneDaySamples = PersistedHistoryStore.retained(oneDaySamples)
            settings.updateOneDayHistorySampleCount(oneDaySamples.count)
            persistOneDayHistoryIfEnabled()
        }
        publishHistories()
    }

    private func appendLive(_ value: Double, to history: inout [Double]) {
        history.append(value)
        let limit = maximumLiveHistoryCount
        if history.count > limit {
            history.removeFirst(history.count - limit)
        }
    }

    private var maximumLiveHistoryCount: Int {
        max(2, Int(Double(HistoryRange.oneHour.seconds) / refreshInterval))
    }

    private func trimLiveHistories() {
        let limit = maximumLiveHistoryCount
        liveCPUHistory = Array(liveCPUHistory.suffix(limit))
        liveMemoryHistory = Array(liveMemoryHistory.suffix(limit))
        liveDownloadHistory = Array(liveDownloadHistory.suffix(limit))
        liveUploadHistory = Array(liveUploadHistory.suffix(limit))
        liveInterfaceDownloadHistory = liveInterfaceDownloadHistory.mapValues {
            Array($0.suffix(limit))
        }
        liveInterfaceUploadHistory = liveInterfaceUploadHistory.mapValues {
            Array($0.suffix(limit))
        }
    }

    func updateHistoryRange() {
        publishHistories()
    }

    private func publishHistories() {
        if settings.historyRange == .oneDay {
            let samples = oneDayDisplaySamples
            cpuHistory = samples.map(\.cpuUsage)
            memoryHistory = samples.map(\.memoryUsage)
            downloadHistory = samples.map(\.downloadRate)
            uploadHistory = samples.map(\.uploadRate)
            interfaceDownloadHistory = dailyInterfaceHistory(samples, download: true)
            interfaceUploadHistory = dailyInterfaceHistory(samples, download: false)
            return
        }

        let limit = max(2, Int(Double(settings.historyRange.seconds) / refreshInterval))
        cpuHistory = Array(liveCPUHistory.suffix(limit))
        memoryHistory = Array(liveMemoryHistory.suffix(limit))
        downloadHistory = Array(liveDownloadHistory.suffix(limit))
        uploadHistory = Array(liveUploadHistory.suffix(limit))
        interfaceDownloadHistory = liveInterfaceDownloadHistory.mapValues {
            Array($0.suffix(limit))
        }
        interfaceUploadHistory = liveInterfaceUploadHistory.mapValues {
            Array($0.suffix(limit))
        }
    }

    private var oneDayDisplaySamples: [MinuteHistorySample] {
        guard let currentSample = minuteHistoryAccumulator.currentSample else {
            return oneDaySamples
        }
        if oneDaySamples.last?.sampledAt == currentSample.sampledAt {
            return Array(oneDaySamples.dropLast()) + [currentSample]
        }
        return oneDaySamples + [currentSample]
    }

    private func dailyInterfaceHistory(
        _ samples: [MinuteHistorySample],
        download: Bool
    ) -> [String: [Double]] {
        let names = Set(samples.flatMap { sample in
            let rates = download ? sample.interfaceDownloadRates : sample.interfaceUploadRates
            return rates.keys
        })
        return Dictionary(uniqueKeysWithValues: names.map { name in
            let values = samples.compactMap { sample in
                download ? sample.interfaceDownloadRates[name] : sample.interfaceUploadRates[name]
            }
            return (name, values)
        })
    }

    private func loadPersistedHistory(from store: PersistedHistoryStore) {
        historyLoadTask = Task { [weak self] in
            do {
                let loadedSamples = try await store.load()
                guard !Task.isCancelled else { return }
                self?.mergePersistedHistory(loadedSamples)
            } catch {
                self?.hasLoadedPersistedHistory = true
                self?.shouldPersistAfterLoad = false
                self?.settings.errorMessage =
                    "Saved history could not be loaded: \(error.localizedDescription)"
            }
        }
    }

    private func mergePersistedHistory(_ loadedSamples: [MinuteHistorySample]) {
        var samplesByMinute: [Int64: MinuteHistorySample] = [:]
        for sample in loadedSamples + oneDaySamples {
            let minute = Int64(sample.sampledAt.timeIntervalSince1970 / 60)
            samplesByMinute[minute] = sample
        }
        oneDaySamples = PersistedHistoryStore.retained(Array(samplesByMinute.values))
        hasLoadedPersistedHistory = true
        settings.updateOneDayHistorySampleCount(oneDaySamples.count)
        publishHistories()
        if shouldPersistAfterLoad {
            shouldPersistAfterLoad = false
            persistOneDayHistoryIfEnabled()
        }
    }

    private func persistenceSettingDidChange(_ enabled: Bool) {
        if enabled {
            persistOneDayHistoryIfEnabled()
        }
    }

    private func persistOneDayHistoryIfEnabled() {
        guard settings.persistedHistoryEnabled, let persistedHistoryStore else { return }
        guard hasLoadedPersistedHistory else {
            shouldPersistAfterLoad = true
            return
        }
        let samples = oneDaySamples
        let previousTask = historyPersistenceTask
        historyPersistenceTask = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            do {
                try await persistedHistoryStore.save(samples)
            } catch {
                self?.settings.errorMessage =
                    "History could not be saved: \(error.localizedDescription)"
            }
        }
    }

    private func clearHistory() {
        historyLoadTask?.cancel()
        hasLoadedPersistedHistory = true
        shouldPersistAfterLoad = false
        oneDaySamples = []
        minuteHistoryAccumulator.clear()
        settings.updateOneDayHistorySampleCount(0)
        publishHistories()

        guard let persistedHistoryStore else { return }
        let previousTask = historyPersistenceTask
        historyPersistenceTask = Task { [weak self] in
            await previousTask?.value
            do {
                try await persistedHistoryStore.clear()
            } catch {
                self?.settings.errorMessage =
                    "Saved history could not be cleared: \(error.localizedDescription)"
            }
        }
    }
}
