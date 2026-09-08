import Foundation

struct ProcessSnapshot: Identifiable, Equatable, Codable, Sendable {
    let pid: Int32
    let name: String
    let cpuUsage: Double
    let memoryBytes: UInt64

    var id: Int32 { pid }
}

struct DiskVolumeSnapshot: Identifiable, Equatable, Codable, Sendable {
    let name: String
    let path: String
    let used: UInt64
    let total: UInt64
    let isInternal: Bool

    var id: String { path }

    var usage: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total)
    }
}

struct NetworkInterfaceSnapshot: Identifiable, Equatable, Codable, Sendable {
    let name: String
    let downloadRate: Double
    let uploadRate: Double

    var id: String { name }
}

enum ThermalLevel: String, Equatable, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    var title: String { rawValue.capitalized }
}

struct BatterySnapshot: Equatable, Codable, Sendable {
    let isPresent: Bool
    let percentage: Double
    let isCharging: Bool
    let isOnACPower: Bool
    let timeRemaining: TimeInterval?
    let cycleCount: Int?
    let healthPercentage: Double?
    let designCapacityMilliampHours: Int?
    let fullChargeCapacityMilliampHours: Int?

    static let unavailable = BatterySnapshot(
        isPresent: false,
        percentage: 0,
        isCharging: false,
        isOnACPower: false,
        timeRemaining: nil,
        cycleCount: nil,
        healthPercentage: nil,
        designCapacityMilliampHours: nil,
        fullChargeCapacityMilliampHours: nil
    )
}

struct SystemSnapshot: Equatable, Codable, Sendable {
    let cpuUsage: Double
    let perCoreUsage: [Double]
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let swapUsed: UInt64
    let swapTotal: UInt64
    let diskUsed: UInt64
    let diskTotal: UInt64
    let volumes: [DiskVolumeSnapshot]
    let downloadRate: Double
    let uploadRate: Double
    let networkInterfaces: [NetworkInterfaceSnapshot]
    let battery: BatterySnapshot
    let topProcesses: [ProcessSnapshot]
    let thermalLevel: ThermalLevel
    let systemUptime: TimeInterval
    let loadAverages: [Double]
    let sampledAt: Date

    static let empty = SystemSnapshot(
        cpuUsage: 0,
        perCoreUsage: [],
        memoryUsed: 0,
        memoryTotal: ProcessInfo.processInfo.physicalMemory,
        swapUsed: 0,
        swapTotal: 0,
        diskUsed: 0,
        diskTotal: 0,
        volumes: [],
        downloadRate: 0,
        uploadRate: 0,
        networkInterfaces: [],
        battery: .unavailable,
        topProcesses: [],
        thermalLevel: .nominal,
        systemUptime: ProcessInfo.processInfo.systemUptime,
        loadAverages: [0, 0, 0],
        sampledAt: .now
    )

    var memoryUsage: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal)
    }

    var diskUsage: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskUsed) / Double(diskTotal)
    }
}
