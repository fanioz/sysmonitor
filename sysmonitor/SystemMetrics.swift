//
//  SystemMetrics.swift
//  sysmonitor
//
//  Data models for all system metrics.
//  Used by collectors and displayed in the status bar and widget UI.
//
//  Requirements: REQ-018 through REQ-045
//

import Foundation

// MARK: - CPU Metrics (REQ-018, REQ-019, REQ-022)

struct CPUMetrics {
    /// Aggregate CPU usage across all cores, 0–100 (REQ-018).
    var aggregateUsage: Double = 0

    /// Per-core CPU usage, each 0–100 (REQ-019).
    var perCoreUsage: [Double] = []

    /// Estimated CPU temperature in °C, nil if unavailable (REQ-022).
    var temperature: Double? = nil
}

// MARK: - RAM Metrics (REQ-026)

struct RAMMetrics {
    /// Total physical RAM in bytes.
    var totalBytes: UInt64 = 0

    /// RAM used by applications in bytes.
    var appMemoryBytes: UInt64 = 0

    /// Wired (non-purgeable) memory in bytes.
    var wiredBytes: UInt64 = 0

    /// Compressed memory in bytes.
    var compressedBytes: UInt64 = 0

    /// Swap space currently used in bytes.
    var swapUsedBytes: UInt64 = 0

    /// Combined used memory: app + wired + compressed.
    var usedBytes: UInt64 {
        appMemoryBytes + wiredBytes + compressedBytes
    }

    /// Usage as a percentage (0–100).
    var usagePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100.0
    }

    /// Total RAM in GB.
    var totalGB: Double {
        Double(totalBytes) / 1_073_741_824.0
    }

    /// Used RAM in GB.
    var usedGB: Double {
        Double(usedBytes) / 1_073_741_824.0
    }

    /// Swap used in GB.
    var swapUsedGB: Double {
        Double(swapUsedBytes) / 1_073_741_824.0
    }
}

// MARK: - Disk Metrics (REQ-032, REQ-034)

struct DiskMetrics {
    /// Total disk capacity in bytes.
    var totalBytes: UInt64 = 0

    /// Used disk space in bytes.
    var usedBytes: UInt64 = 0

    /// Read speed in bytes/sec.
    var readBytesPerSec: Double = 0

    /// Write speed in bytes/sec.
    var writeBytesPerSec: Double = 0

    /// Usage as a percentage (0–100).
    var usagePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100.0
    }

    /// Total capacity in GB.
    var totalGB: Double {
        Double(totalBytes) / 1_073_741_824.0
    }

    /// Used space in GB.
    var usedGB: Double {
        Double(usedBytes) / 1_073_741_824.0
    }
}

// MARK: - Network Metrics (REQ-038, REQ-041)

struct NetworkMetrics {
    /// Download speed in bytes/sec.
    var downloadBytesPerSec: Double = 0

    /// Upload speed in bytes/sec.
    var uploadBytesPerSec: Double = 0

    /// Cumulative bytes downloaded since app launch.
    var totalDownloadedBytes: UInt64 = 0

    /// Cumulative bytes uploaded since app launch.
    var totalUploadedBytes: UInt64 = 0

    /// Name of the active network interface (e.g. "en0").
    var interfaceName: String? = nil

    /// Whether a network interface is available.
    var isConnected: Bool {
        interfaceName != nil
    }

    /// Download speed in MB/s.
    var downloadMBPerSec: Double {
        downloadBytesPerSec / 1_048_576.0
    }

    /// Upload speed in MB/s.
    var uploadMBPerSec: Double {
        uploadBytesPerSec / 1_048_576.0
    }

    /// Combined throughput in MB/s.
    var combinedMBPerSec: Double {
        downloadMBPerSec + uploadMBPerSec
    }

    /// Total downloaded in GB.
    var totalDownloadedGB: Double {
        Double(totalDownloadedBytes) / 1_073_741_824.0
    }

    /// Total uploaded in GB.
    var totalUploadedGB: Double {
        Double(totalUploadedBytes) / 1_073_741_824.0
    }
}

// MARK: - Aggregate

/// Container for all system metric snapshots.
struct SystemMetrics {
    var cpu: CPUMetrics = CPUMetrics()
    var ram: RAMMetrics = RAMMetrics()
    var disk: DiskMetrics = DiskMetrics()
    var network: NetworkMetrics = NetworkMetrics()
    var timestamp: Date = Date()

    /// Whether this snapshot contains stale data from a failed collection (REQ-054).
    var isStale: Bool = false

    /// Descriptions of any collection errors that occurred.
    var collectionErrors: [String] = []
}
