import Darwin
import Foundation
import IOKit.ps

final class SystemSampler {
    private struct CPUTicks {
        let used: UInt64
        let total: UInt64
    }

    private struct DiskSample {
        let primary: (used: UInt64, total: UInt64)
        let volumes: [DiskVolumeSnapshot]

        static let empty = DiskSample(primary: (0, 0), volumes: [])
    }

    private var previousCPUTicks: (used: UInt64, total: UInt64)?
    private var previousPerCoreTicks: [CPUTicks] = []
    private var previousNetworkBytes: (received: UInt64, sent: UInt64, date: Date)?
    private var previousNetworkInterfaceBytes: [String: (received: UInt64, sent: UInt64)] = [:]
    private var previousProcessTimes: [pid_t: UInt64] = [:]
    private var previousProcessSampleDate: Date?
    private var cachedTopProcesses: [ProcessSnapshot] = []
    private var cachedDisk = DiskSample.empty
    private var previousDiskSampleDate: Date?
    private var cachedBattery = BatterySnapshot.unavailable
    private var previousBatterySampleDate: Date?

    func sample(forceSlowMetrics: Bool = false) -> SystemSnapshot {
        let now = Date()
        let cpu = sampleCPU()
        let memory = sampleMemory()
        let disk = sampleDiskIfNeeded(at: now, force: forceSlowMetrics)
        let network = sampleNetwork(at: now)

        return SystemSnapshot(
            cpuUsage: cpu.total,
            perCoreUsage: cpu.perCore,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            swapUsed: memory.swapUsed,
            swapTotal: memory.swapTotal,
            diskUsed: disk.used,
            diskTotal: disk.total,
            volumes: cachedDisk.volumes,
            downloadRate: network.download,
            uploadRate: network.upload,
            networkInterfaces: network.interfaces,
            battery: sampleBatteryIfNeeded(at: now, force: forceSlowMetrics),
            topProcesses: sampleProcesses(at: now),
            thermalLevel: sampleThermalLevel(),
            systemUptime: ProcessInfo.processInfo.systemUptime,
            loadAverages: sampleLoadAverages(),
            sampledAt: now
        )
    }

    private func sampleCPU() -> (total: Double, perCore: [Double]) {
        var coreCount: natural_t = 0
        var rawInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &coreCount,
            &rawInfo,
            &infoCount
        )

        guard result == KERN_SUCCESS, let rawInfo else { return (0, []) }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: rawInfo)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let stateCount = Int(CPU_STATE_MAX)
        var ticks: [CPUTicks] = []
        ticks.reserveCapacity(Int(coreCount))

        for core in 0..<Int(coreCount) {
            let base = core * stateCount
            let user = UInt64(rawInfo[base + Int(CPU_STATE_USER)])
            let system = UInt64(rawInfo[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(rawInfo[base + Int(CPU_STATE_IDLE)])
            let nice = UInt64(rawInfo[base + Int(CPU_STATE_NICE)])
            let used = user + system + nice
            ticks.append(CPUTicks(used: used, total: used + idle))
        }

        let aggregateUsed = ticks.reduce(0) { $0 + $1.used }
        let aggregateTotal = ticks.reduce(0) { $0 + $1.total }
        let totalUsage = usage(
            current: CPUTicks(used: aggregateUsed, total: aggregateTotal),
            previous: previousCPUTicks.map(CPUTicks.init)
        )

        let perCoreUsage = ticks.enumerated().map { index, current in
            usage(
                current: current,
                previous: index < previousPerCoreTicks.count ? previousPerCoreTicks[index] : nil
            )
        }

        previousCPUTicks = (aggregateUsed, aggregateTotal)
        previousPerCoreTicks = ticks
        return (totalUsage, perCoreUsage)
    }

    private func usage(current: CPUTicks, previous: CPUTicks?) -> Double {
        guard let previous,
              current.total >= previous.total,
              current.used >= previous.used else { return 0 }
        let totalDelta = current.total - previous.total
        guard totalDelta > 0 else { return 0 }
        return min(1, max(0, Double(current.used - previous.used) / Double(totalDelta)))
    }

    private func sampleMemory() -> (used: UInt64, total: UInt64, swapUsed: UInt64, swapTotal: UInt64) {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return (0, total, 0, 0) }

        var rawPageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &rawPageSize) == KERN_SUCCESS else {
            return (0, total, 0, 0)
        }
        let pageSize = UInt64(rawPageSize)
        let active = UInt64(info.active_count) * pageSize
        let wired = UInt64(info.wire_count) * pageSize
        let compressed = UInt64(info.compressor_page_count) * pageSize
        let used = min(total, active + wired + compressed)
        let swap = sampleSwap()
        return (used, total, swap.used, swap.total)
    }

    private func sampleSwap() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return (0, 0) }
        return (UInt64(usage.xsu_used), UInt64(usage.xsu_total))
    }

    private func sampleDisk() -> DiskSample {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeNameKey,
            .volumeIsLocalKey,
            .volumeIsInternalKey,
            .volumeIsBrowsableKey
        ]
        let rootURL = URL(fileURLWithPath: "/")
        let mountedURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? [rootURL]

        var volumes = mountedURLs.compactMap { url -> DiskVolumeSnapshot? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsLocal != false,
                  values.volumeIsBrowsable != false,
                  let rawTotal = values.volumeTotalCapacity,
                  rawTotal > 0 else { return nil }

            let total = UInt64(rawTotal)
            let available = UInt64(max(0, values.volumeAvailableCapacity ?? 0))
            return DiskVolumeSnapshot(
                name: values.volumeName ?? url.lastPathComponent,
                path: url.path,
                used: total > available ? total - available : 0,
                total: total,
                isInternal: values.volumeIsInternal ?? false
            )
        }

        volumes.sort {
            if $0.path == "/" { return true }
            if $1.path == "/" { return false }
            if $0.isInternal != $1.isInternal { return $0.isInternal }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let root = volumes.first(where: { $0.path == "/" }) ?? volumes.first
        return DiskSample(
            primary: (root?.used ?? 0, root?.total ?? 0),
            volumes: volumes
        )
    }

    private func sampleDiskIfNeeded(
        at now: Date,
        force: Bool
    ) -> (used: UInt64, total: UInt64) {
        if force || previousDiskSampleDate == nil
            || now.timeIntervalSince(previousDiskSampleDate!) >= 60 {
            cachedDisk = sampleDisk()
            previousDiskSampleDate = now
        }
        return cachedDisk.primary
    }

    private func sampleNetwork(
        at now: Date
    ) -> (download: Double, upload: Double, interfaces: [NetworkInterfaceSnapshot]) {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return (0, 0, []) }
        defer { freeifaddrs(firstAddress) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var interfaceBytes: [String: (received: UInt64, sent: UInt64)] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let address = current {
            let interface = address.pointee
            let name = String(cString: interface.ifa_name)
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp,
               !isLoopback,
               name.hasPrefix("en"),
               interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let rawData = interface.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                let interfaceReceived = UInt64(data.ifi_ibytes)
                let interfaceSent = UInt64(data.ifi_obytes)
                received += interfaceReceived
                sent += interfaceSent
                interfaceBytes[name] = (interfaceReceived, interfaceSent)
            }

            current = interface.ifa_next
        }

        defer {
            previousNetworkBytes = (received, sent, now)
            previousNetworkInterfaceBytes = interfaceBytes
        }
        guard let previous = previousNetworkBytes,
              received >= previous.received,
              sent >= previous.sent else { return (0, 0, []) }

        let elapsed = now.timeIntervalSince(previous.date)
        guard elapsed > 0 else { return (0, 0, []) }

        let interfaces = interfaceBytes.compactMap { name, current -> NetworkInterfaceSnapshot? in
            guard let prior = previousNetworkInterfaceBytes[name],
                  current.received >= prior.received,
                  current.sent >= prior.sent else { return nil }
            return NetworkInterfaceSnapshot(
                name: name,
                downloadRate: Double(current.received - prior.received) / elapsed,
                uploadRate: Double(current.sent - prior.sent) / elapsed
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return (
            Double(received - previous.received) / elapsed,
            Double(sent - previous.sent) / elapsed,
            interfaces
        )
    }

    private func sampleBattery() -> BatterySnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                as? [String: Any] else { return .unavailable }

        let current = description[kIOPSCurrentCapacityKey] as? Double
            ?? Double(description[kIOPSCurrentCapacityKey] as? Int ?? 0)
        let maximum = description[kIOPSMaxCapacityKey] as? Double
            ?? Double(description[kIOPSMaxCapacityKey] as? Int ?? 100)
        let percentage = maximum > 0 ? current / maximum : 0
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let powerState = description[kIOPSPowerSourceStateKey] as? String
        let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Double
            ?? Double(description[kIOPSTimeToEmptyKey] as? Int ?? -1)

        let health = sampleBatteryHealth()

        return BatterySnapshot(
            isPresent: true,
            percentage: min(1, max(0, percentage)),
            isCharging: isCharging,
            isOnACPower: powerState == kIOPSACPowerValue,
            timeRemaining: timeToEmpty > 0 ? timeToEmpty * 60 : nil,
            cycleCount: health.cycleCount,
            healthPercentage: health.percentage,
            designCapacityMilliampHours: health.designCapacityMilliampHours,
            fullChargeCapacityMilliampHours: health.fullChargeCapacityMilliampHours
        )
    }

    private func sampleBatteryIfNeeded(at now: Date, force: Bool) -> BatterySnapshot {
        if force || previousBatterySampleDate == nil
            || now.timeIntervalSince(previousBatterySampleDate!) >= 30 {
            cachedBattery = sampleBattery()
            previousBatterySampleDate = now
        }
        return cachedBattery
    }

    private func sampleBatteryHealth() -> (
        cycleCount: Int?,
        percentage: Double?,
        designCapacityMilliampHours: Int?,
        fullChargeCapacityMilliampHours: Int?
    ) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return (nil, nil, nil, nil) }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any] else {
            return (nil, nil, nil, nil)
        }

        func integer(_ key: String) -> Int? {
            if let value = properties[key] as? Int { return value }
            if let value = properties[key] as? NSNumber { return value.intValue }
            return nil
        }

        let cycles = integer("CycleCount")
        let design = integer("DesignCapacity").flatMap { $0 > 0 ? $0 : nil }
        let maximum = (integer("AppleRawMaxCapacity") ?? integer("NominalChargeCapacity"))
            .flatMap { $0 > 0 ? $0 : nil }
        let percentage: Double?
        if let design, let maximum, design > 0 {
            percentage = min(1.2, max(0, Double(maximum) / Double(design)))
        } else {
            percentage = nil
        }
        return (cycles, percentage, design, maximum)
    }

    private func sampleProcesses(at now: Date) -> [ProcessSnapshot] {
        if let previousProcessSampleDate,
           now.timeIntervalSince(previousProcessSampleDate) < 5 {
            return cachedTopProcesses
        }

        let requiredBytes = proc_listallpids(nil, 0)
        guard requiredBytes > 0 else { return cachedTopProcesses }

        let capacity = Int(requiredBytes) / MemoryLayout<pid_t>.stride + 32
        var pids = [pid_t](repeating: 0, count: capacity)
        let filledBytes = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard filledBytes > 0 else { return cachedTopProcesses }

        let elapsed = previousProcessSampleDate.map { now.timeIntervalSince($0) }
        var currentTimes: [pid_t: UInt64] = [:]
        var processes: [ProcessSnapshot] = []

        for pid in pids.prefix(Int(filledBytes) / MemoryLayout<pid_t>.stride) where pid > 0 {
            var info = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let bytesRead = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, infoSize)
            guard bytesRead == infoSize else { continue }

            let totalTime = info.pti_total_user + info.pti_total_system
            currentTimes[pid] = totalTime

            let cpuUsage: Double
            if let elapsed,
               elapsed > 0,
               let previous = previousProcessTimes[pid],
               totalTime >= previous {
                cpuUsage = Double(totalTime - previous) / (elapsed * 1_000_000_000)
            } else {
                cpuUsage = 0
            }

            guard cpuUsage > 0.001 || info.pti_resident_size > 0 else { continue }
            let name = processName(for: pid)
            guard !name.isEmpty else { continue }

            processes.append(ProcessSnapshot(
                pid: pid,
                name: name,
                cpuUsage: max(0, cpuUsage),
                memoryBytes: info.pti_resident_size
            ))
        }

        previousProcessTimes = currentTimes
        previousProcessSampleDate = now
        let byCPU = processes.sorted {
                if abs($0.cpuUsage - $1.cpuUsage) > 0.001 {
                    return $0.cpuUsage > $1.cpuUsage
                }
                return $0.memoryBytes > $1.memoryBytes
            }
            .prefix(20)
        let byMemory = processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(20)
        var seenPIDs: Set<pid_t> = []
        cachedTopProcesses = (Array(byCPU) + Array(byMemory)).filter {
            seenPIDs.insert($0.pid).inserted
        }
        return cachedTopProcesses
    }

    private func processName(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func sampleThermalLevel() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    private func sampleLoadAverages() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        let count = values.withUnsafeMutableBufferPointer { buffer in
            getloadavg(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [0, 0, 0] }
        return values
    }
}
