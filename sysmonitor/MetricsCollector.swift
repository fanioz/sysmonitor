//
//  MetricsCollector.swift
//  sysmonitor
//
//  Collects CPU, RAM, Disk, and Network metrics using system APIs.
//  CPU/Network usage is calculated as a delta between successive samples.
//
//  Requirements: REQ-018, REQ-019, REQ-022, REQ-026, REQ-032, REQ-034,
//                REQ-038, REQ-041, REQ-043, REQ-045, REQ-054, REQ-055
//

import Foundation
import Darwin
import IOKit

/// Collects all system metrics using Mach, sysctl, IOKit, and BSD APIs.
/// Delta-based metrics (CPU, network, disk I/O) require at least two samples.
final class MetricsCollector {

    // MARK: - CPU State

    /// Previous per-core CPU ticks for delta computation.
    private var previousPerCoreTicks: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []

    // MARK: - Network State

    /// Previous network byte counters for speed computation.
    private var previousNetworkBytes: (received: UInt64, sent: UInt64)?

    /// Time of the previous network sample.
    private var lastNetworkSampleTime: Date?

    /// Cumulative download bytes since app launch.
    private var cumulativeDownloadBytes: UInt64 = 0

    /// Cumulative upload bytes since app launch.
    private var cumulativeUploadBytes: UInt64 = 0

    /// Baseline network bytes at app launch (for cumulative tracking).
    private var baselineNetworkBytes: (received: UInt64, sent: UInt64)?

    /// Currently tracked active interface name.
    private var trackedInterfaceName: String?

    // MARK: - Disk I/O State

    /// Previous disk I/O byte counters for speed computation.
    private var previousDiskIO: (read: UInt64, write: UInt64)?

    /// Time of the previous disk I/O sample.
    private var lastDiskIOSampleTime: Date?

    // MARK: - Self-Throttling State (REQ-055)

    /// Rolling CPU time samples for self-monitoring (timestamp, cpuTime).
    private var selfCPUSamples: [(timestamp: Date, cpuTime: TimeInterval)] = []

    /// Whether self-throttling is currently active.
    private(set) var isSelfThrottled: Bool = false

    // MARK: - CPU Collection (REQ-018, REQ-019)

    /// Collects current CPU usage by computing the delta from the previous sample.
    /// The first call will return zero usage (establishing a baseline).
    func collectCPU() -> CPUMetrics {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS, let info = processorInfo else {
            return CPUMetrics()
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(Int(processorInfoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let coreCount = Int(processorCount)
        var currentTicks: [(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)] = []
        currentTicks.reserveCapacity(coreCount)

        for i in 0..<coreCount {
            let offset = Int32(i) * CPU_STATE_MAX
            let user   = UInt64(info[Int(offset + CPU_STATE_USER)])
            let system = UInt64(info[Int(offset + CPU_STATE_SYSTEM)])
            let idle   = UInt64(info[Int(offset + CPU_STATE_IDLE)])
            let nice   = UInt64(info[Int(offset + CPU_STATE_NICE)])
            currentTicks.append((user: user, system: system, idle: idle, nice: nice))
        }

        var perCoreUsage: [Double] = []
        perCoreUsage.reserveCapacity(coreCount)

        var totalUsed: UInt64 = 0
        var totalAll: UInt64 = 0

        if previousPerCoreTicks.count == coreCount {
            for i in 0..<coreCount {
                let prev = previousPerCoreTicks[i]
                let curr = currentTicks[i]

                let dUser   = curr.user   - prev.user
                let dSystem = curr.system - prev.system
                let dIdle   = curr.idle   - prev.idle
                let dNice   = curr.nice   - prev.nice

                let used = dUser + dSystem + dNice
                let total = used + dIdle

                let usage = total > 0 ? Double(used) / Double(total) * 100.0 : 0
                perCoreUsage.append(usage)

                totalUsed += used
                totalAll += total
            }
        } else {
            perCoreUsage = Array(repeating: 0, count: coreCount)
        }

        previousPerCoreTicks = currentTicks

        let aggregate = totalAll > 0 ? Double(totalUsed) / Double(totalAll) * 100.0 : 0

        // REQ-022: CPU temperature via SMC (best-effort, nil if sandbox-blocked).
        let temperature = readCPUTemperature()

        return CPUMetrics(
            aggregateUsage: aggregate,
            perCoreUsage: perCoreUsage,
            temperature: temperature
        )
    }

    // MARK: - CPU Temperature (REQ-022)

    /// Attempts to read CPU temperature via IOKit SMC.
    /// Returns nil if unavailable (sandbox, Apple Silicon, or access denied).
    private func readCPUTemperature() -> Double? {
        // SMC access requires a connection to "AppleSMC" which is typically
        // blocked by the App Sandbox. Return nil gracefully.
        // A future non-sandboxed build could implement full SMC reading here.
        return nil
    }

    // MARK: - RAM Collection (REQ-026)

    /// Collects current RAM usage using `host_statistics64`.
    func collectRAM() -> RAMMetrics {
        let hostPort = mach_host_self()
        let totalBytes = ProcessInfo.processInfo.physicalMemory

        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return RAMMetrics(totalBytes: totalBytes)
        }

        let pageSize = UInt64(vm_kernel_page_size)

        let internalPages = UInt64(vmStats.internal_page_count)
        let purgeablePages = UInt64(vmStats.purgeable_count)
        let appMemory = (internalPages - purgeablePages) * pageSize

        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize

        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapResult = sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)
        let swapUsed: UInt64 = swapResult == 0 ? swapUsage.xsu_used : 0

        return RAMMetrics(
            totalBytes: totalBytes,
            appMemoryBytes: appMemory,
            wiredBytes: wired,
            compressedBytes: compressed,
            swapUsedBytes: swapUsed
        )
    }

    // MARK: - Disk Collection (REQ-032, REQ-034)

    /// Collects disk space usage for the primary volume and I/O speeds.
    func collectDisk() -> DiskMetrics {
        var metrics = DiskMetrics()

        // REQ-032: Disk space via FileManager (works in sandbox).
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: "/")
            if let totalSize = attrs[.systemSize] as? UInt64,
               let freeSize = attrs[.systemFreeSize] as? UInt64 {
                metrics.totalBytes = totalSize
                metrics.usedBytes = totalSize - freeSize
            }
        } catch {
            // Will be reported as stale if this fails.
        }

        // REQ-034: Disk I/O speed via IOKit (best-effort).
        let now = Date()
        if let currentIO = readDiskIOBytes() {
            if let prevIO = previousDiskIO, let prevTime = lastDiskIOSampleTime {
                let elapsed = now.timeIntervalSince(prevTime)
                if elapsed > 0 {
                    let readDelta = currentIO.read >= prevIO.read ? currentIO.read - prevIO.read : 0
                    let writeDelta = currentIO.write >= prevIO.write ? currentIO.write - prevIO.write : 0
                    metrics.readBytesPerSec = Double(readDelta) / elapsed
                    metrics.writeBytesPerSec = Double(writeDelta) / elapsed
                }
            }
            previousDiskIO = currentIO
            lastDiskIOSampleTime = now
        }

        return metrics
    }

    /// Reads cumulative disk I/O bytes via IOKit IOBlockStorageDriver.
    /// Returns nil if IOKit access is blocked by the sandbox.
    private func readDiskIOBytes() -> (read: UInt64, write: UInt64)? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var disk = IOIteratorNext(iterator)
        while disk != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(disk, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = properties?.takeRetainedValue() as? [String: Any],
               let stats = props["Statistics"] as? [String: Any] {
                if let readBytes = stats["Bytes (Read)"] as? UInt64 {
                    totalRead += readBytes
                }
                if let writeBytes = stats["Bytes (Write)"] as? UInt64 {
                    totalWrite += writeBytes
                }
            }
            IOObjectRelease(disk)
            disk = IOIteratorNext(iterator)
        }

        return (read: totalRead, write: totalWrite)
    }

    // MARK: - Network Collection (REQ-038, REQ-041, REQ-043, REQ-045)

    /// Collects network throughput, cumulative usage, and interface status.
    func collectNetwork() -> NetworkMetrics {
        var metrics = NetworkMetrics()
        let now = Date()

        // Read raw byte counters from all physical interfaces via getifaddrs.
        let (totalReceived, totalSent, activeInterface) = readNetworkBytes()

        // REQ-043: Detect interface change — reset counters on switch.
        if let active = activeInterface {
            if let tracked = trackedInterfaceName, tracked != active {
                // Interface changed — reset baselines and cumulative counters.
                previousNetworkBytes = nil
                lastNetworkSampleTime = nil
                baselineNetworkBytes = (received: totalReceived, sent: totalSent)
                cumulativeDownloadBytes = 0
                cumulativeUploadBytes = 0
            }
            trackedInterfaceName = active
            metrics.interfaceName = active
        } else {
            // REQ-045: No active interface — suspend network metrics.
            trackedInterfaceName = nil
            metrics.interfaceName = nil
            previousNetworkBytes = nil
            lastNetworkSampleTime = nil
            return metrics
        }

        // Set baseline on first sample.
        if baselineNetworkBytes == nil {
            baselineNetworkBytes = (received: totalReceived, sent: totalSent)
        }

        // Calculate speed from delta (bytes/sec).
        if let prevBytes = previousNetworkBytes, let prevTime = lastNetworkSampleTime {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let dlDelta = totalReceived >= prevBytes.received ? totalReceived - prevBytes.received : 0
                let ulDelta = totalSent >= prevBytes.sent ? totalSent - prevBytes.sent : 0
                metrics.downloadBytesPerSec = Double(dlDelta) / elapsed
                metrics.uploadBytesPerSec = Double(ulDelta) / elapsed
            }
        }

        previousNetworkBytes = (received: totalReceived, sent: totalSent)
        lastNetworkSampleTime = now

        // REQ-041: Cumulative bytes since app launch (relative to baseline).
        if let baseline = baselineNetworkBytes {
            cumulativeDownloadBytes = totalReceived >= baseline.received ? totalReceived - baseline.received : 0
            cumulativeUploadBytes = totalSent >= baseline.sent ? totalSent - baseline.sent : 0
        }
        metrics.totalDownloadedBytes = cumulativeDownloadBytes
        metrics.totalUploadedBytes = cumulativeUploadBytes

        return metrics
    }

    /// Reads raw byte counters from physical network interfaces via `getifaddrs`.
    /// Returns total received/sent bytes and the name of the first active interface.
    private func readNetworkBytes() -> (received: UInt64, sent: UInt64, activeInterface: String?) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (0, 0, nil)
        }
        defer { freeifaddrs(ifaddr) }

        var totalReceived: UInt64 = 0
        var totalSent: UInt64 = 0
        var activeInterface: String?

        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let entry = current {
            let iface = entry.pointee
            let name = String(cString: iface.ifa_name)

            // Only count physical/bridge interfaces (en*, bridge*).
            if let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                let isPhysical = name.hasPrefix("en") || name.hasPrefix("bridge")
                if isPhysical {
                    if let data = iface.ifa_data {
                        let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                        totalReceived += UInt64(ifData.ifi_ibytes)
                        totalSent += UInt64(ifData.ifi_obytes)
                    }

                    // Track the first active and running interface.
                    if activeInterface == nil {
                        let flags = Int32(iface.ifa_flags)
                        let isUp = (flags & IFF_UP) != 0
                        let isRunning = (flags & IFF_RUNNING) != 0
                        if isUp && isRunning {
                            activeInterface = name
                        }
                    }
                }
            }

            current = iface.ifa_next
        }

        return (received: totalReceived, sent: totalSent, activeInterface: activeInterface)
    }

    // MARK: - Self-Throttling (REQ-055)

    /// Checks whether the app's own CPU usage exceeds 5% over 30 seconds.
    /// Call this each poll cycle; it updates `isSelfThrottled`.
    func checkSelfThrottling() {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)

        let cpuTime = TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000.0
                    + TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000.0

        let now = Date()
        selfCPUSamples.append((timestamp: now, cpuTime: cpuTime))

        // Keep only the last 30 seconds of samples.
        let cutoff = now.addingTimeInterval(-30)
        selfCPUSamples.removeAll { $0.timestamp < cutoff }

        // Need at least 2 samples spanning some time to compute a rate.
        guard selfCPUSamples.count >= 2,
              let first = selfCPUSamples.first,
              let last = selfCPUSamples.last else {
            isSelfThrottled = false
            return
        }

        let wallTime = last.timestamp.timeIntervalSince(first.timestamp)
        guard wallTime > 5 else {
            // Not enough data yet.
            isSelfThrottled = false
            return
        }

        let cpuTimeDelta = last.cpuTime - first.cpuTime
        let cpuPercent = (cpuTimeDelta / wallTime) * 100.0

        // REQ-055: Throttle if >5% CPU on average over 30 seconds.
        isSelfThrottled = cpuPercent > 5.0
    }

    // MARK: - Collect All

    /// Collects all metrics in one call. Marks the result as stale if any
    /// collection fails, retaining the last known good values.
    func collectAll(previous: SystemMetrics? = nil) -> SystemMetrics {
        var metrics = SystemMetrics()
        var errors: [String] = []

        // CPU
        let cpu = collectCPU()
        if cpu.perCoreUsage.isEmpty && previous != nil {
            metrics.cpu = previous!.cpu
            errors.append("CPU data unavailable")
        } else {
            metrics.cpu = cpu
        }

        // RAM
        let ram = collectRAM()
        if ram.totalBytes == 0 && previous != nil {
            metrics.ram = previous!.ram
            errors.append("RAM data unavailable")
        } else {
            metrics.ram = ram
        }

        // Disk
        let disk = collectDisk()
        if disk.totalBytes == 0 && previous != nil {
            metrics.disk = previous!.disk
            errors.append("Disk data unavailable")
        } else {
            metrics.disk = disk
        }

        // Network
        metrics.network = collectNetwork()

        // Stale tracking (REQ-054).
        metrics.isStale = !errors.isEmpty
        metrics.collectionErrors = errors
        metrics.timestamp = Date()

        // Self-throttle check (REQ-055).
        checkSelfThrottling()

        return metrics
    }
}
