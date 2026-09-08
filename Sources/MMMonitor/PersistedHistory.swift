import Foundation

struct MinuteHistorySample: Codable, Equatable, Sendable {
    let sampledAt: Date
    let cpuUsage: Double
    let memoryUsage: Double
    let downloadRate: Double
    let uploadRate: Double
    let interfaceDownloadRates: [String: Double]
    let interfaceUploadRates: [String: Double]
}

struct MinuteHistoryAccumulator: Sendable {
    private var minute: Int64?
    private var sampleCount = 0
    private var cpuTotal = 0.0
    private var memoryTotal = 0.0
    private var downloadTotal = 0.0
    private var uploadTotal = 0.0
    private var interfaceDownloadTotals: [String: Double] = [:]
    private var interfaceUploadTotals: [String: Double] = [:]
    private var interfaceSampleCounts: [String: Int] = [:]

    var currentSample: MinuteHistorySample? {
        guard let minute, sampleCount > 0 else { return nil }
        return MinuteHistorySample(
            sampledAt: Date(timeIntervalSince1970: Double(minute * 60)),
            cpuUsage: cpuTotal / Double(sampleCount),
            memoryUsage: memoryTotal / Double(sampleCount),
            downloadRate: downloadTotal / Double(sampleCount),
            uploadRate: uploadTotal / Double(sampleCount),
            interfaceDownloadRates: averaged(interfaceDownloadTotals),
            interfaceUploadRates: averaged(interfaceUploadTotals)
        )
    }

    mutating func add(_ snapshot: SystemSnapshot) -> MinuteHistorySample? {
        let incomingMinute = Int64(snapshot.sampledAt.timeIntervalSince1970 / 60)
        var completedSample: MinuteHistorySample?

        if minute != incomingMinute {
            completedSample = currentSample
            reset(to: incomingMinute)
        }

        sampleCount += 1
        cpuTotal += snapshot.cpuUsage
        memoryTotal += snapshot.memoryUsage
        downloadTotal += snapshot.downloadRate
        uploadTotal += snapshot.uploadRate

        for interface in snapshot.networkInterfaces {
            interfaceDownloadTotals[interface.name, default: 0] += interface.downloadRate
            interfaceUploadTotals[interface.name, default: 0] += interface.uploadRate
            interfaceSampleCounts[interface.name, default: 0] += 1
        }

        return completedSample
    }

    mutating func clear() {
        minute = nil
        sampleCount = 0
        cpuTotal = 0
        memoryTotal = 0
        downloadTotal = 0
        uploadTotal = 0
        interfaceDownloadTotals = [:]
        interfaceUploadTotals = [:]
        interfaceSampleCounts = [:]
    }

    private func averaged(_ totals: [String: Double]) -> [String: Double] {
        totals.reduce(into: [:]) { result, entry in
            guard let count = interfaceSampleCounts[entry.key], count > 0 else { return }
            result[entry.key] = entry.value / Double(count)
        }
    }

    private mutating func reset(to minute: Int64) {
        clear()
        self.minute = minute
    }
}

actor PersistedHistoryStore {
    static let maximumSampleCount = 1_440
    static let retentionInterval: TimeInterval = 86_400

    private struct Archive: Codable, Sendable {
        let formatVersion: Int
        let samples: [MinuteHistorySample]
    }

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = applicationSupport
                .appendingPathComponent("MMMonitor", isDirectory: true)
                .appendingPathComponent("history-v1.json", isDirectory: false)
        }
    }

    func load() throws -> [MinuteHistorySample] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive = try decoder.decode(Archive.self, from: data)
        guard archive.formatVersion == 1 else { return [] }
        return Self.retained(archive.samples)
    }

    func save(_ samples: [MinuteHistorySample]) throws {
        let retainedSamples = Self.retained(samples)
        let archive = Archive(formatVersion: 1, samples: retainedSamples)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(archive)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    static func retained(
        _ samples: [MinuteHistorySample],
        relativeTo now: Date = .now
    ) -> [MinuteHistorySample] {
        let earliestDate = now.addingTimeInterval(-retentionInterval)
        let latestDate = now.addingTimeInterval(60)
        let validSamples = samples
            .filter { $0.sampledAt >= earliestDate && $0.sampledAt <= latestDate }
            .sorted { $0.sampledAt < $1.sampledAt }
        return Array(validSamples.suffix(maximumSampleCount))
    }
}
