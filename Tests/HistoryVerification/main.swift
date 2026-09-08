import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func snapshot(at date: Date, cpu: Double, interfaceRate: Double) -> SystemSnapshot {
    SystemSnapshot(
        cpuUsage: cpu,
        perCoreUsage: [],
        memoryUsed: 50,
        memoryTotal: 100,
        swapUsed: 0,
        swapTotal: 0,
        diskUsed: 0,
        diskTotal: 0,
        volumes: [],
        downloadRate: interfaceRate,
        uploadRate: interfaceRate / 2,
        networkInterfaces: [
            NetworkInterfaceSnapshot(
                name: "en0",
                downloadRate: interfaceRate,
                uploadRate: interfaceRate / 2
            )
        ],
        battery: .unavailable,
        topProcesses: [],
        thermalLevel: .nominal,
        systemUptime: 0,
        loadAverages: [],
        sampledAt: date
    )
}

let currentMinute = floor(Date.now.timeIntervalSince1970 / 60) * 60
let minuteStart = Date(timeIntervalSince1970: currentMinute - 60)
var accumulator = MinuteHistoryAccumulator()
require(
    accumulator.add(snapshot(at: minuteStart, cpu: 0.2, interfaceRate: 100)) == nil,
    "the first sample should start a bucket"
)
require(
    accumulator.add(
        snapshot(at: minuteStart.addingTimeInterval(30), cpu: 0.4, interfaceRate: 300)
    ) == nil,
    "samples from the same minute should remain in one bucket"
)

let completed = accumulator.add(
    snapshot(at: minuteStart.addingTimeInterval(60), cpu: 0.8, interfaceRate: 500)
)
require(
    abs((completed?.cpuUsage ?? 0) - 0.3) < 0.000_001,
    "CPU samples should be averaged"
)
require(
    abs((completed?.memoryUsage ?? 0) - 0.5) < 0.000_001,
    "memory samples should be averaged"
)
require(
    abs((completed?.interfaceDownloadRates["en0"] ?? 0) - 200) < 0.000_001,
    "interface samples should be averaged"
)
require(
    abs((accumulator.currentSample?.cpuUsage ?? 0) - 0.8) < 0.000_001,
    "a new minute should start with the latest sample"
)

let testDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("MMMonitor-History-\(UUID().uuidString)", isDirectory: true)
let fileURL = testDirectory.appendingPathComponent("history-v1.json")
let store = PersistedHistoryStore(fileURL: fileURL)

guard let completed else {
    require(false, "a completed minute sample is required")
    exit(1)
}

try await store.save([completed])
let loaded = try await store.load()
require(loaded == [completed], "saved history should round-trip")
require(FileManager.default.fileExists(atPath: fileURL.path), "the history file should exist")
try await store.clear()
require(!FileManager.default.fileExists(atPath: fileURL.path), "clear should remove the history file")
try? FileManager.default.removeItem(at: testDirectory)

let oversized = (0..<1_500).map { offset in
    MinuteHistorySample(
        sampledAt: Date.now.addingTimeInterval(Double(offset - 1_499) * 60),
        cpuUsage: 0,
        memoryUsage: 0,
        downloadRate: 0,
        uploadRate: 0,
        interfaceDownloadRates: [:],
        interfaceUploadRates: [:]
    )
}
require(
    PersistedHistoryStore.retained(oversized).count == 1_440,
    "history should be capped at 1,440 samples"
)

print("History aggregation and persistence checks passed")
