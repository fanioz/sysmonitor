//
//  MetricCards.swift
//  sysmonitor
//
//  Data-driven SwiftUI metric cards for CPU, Memory, Disk, and Network.
//
//  Requirements: REQ-020 through REQ-045, REQ-056
//

import SwiftUI

// MARK: - CPU Card

struct CPUCard: View {
    let metrics: CPUMetrics
    
    private var colorForUsage: Color {
        if metrics.aggregateUsage >= 85.0 {
            return .red // REQ-024
        } else if metrics.aggregateUsage >= 60.0 {
            return .orange // REQ-025 (Amber)
        } else {
            return .accentColor // REQ-023
        }
    }
    
    var body: some View {
        CardContainer(title: "CPU", icon: "cpu", value: String(format: "%.0f%%", metrics.aggregateUsage)) {
            VStack(alignment: .leading, spacing: 12) {
                // REQ-020: Placeholder line graph
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 40)
                    .overlay(Text("Graph Placeholder").font(.caption2).foregroundStyle(.secondary))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                
                // REQ-021: Per-core vertical bars
                if !metrics.perCoreUsage.isEmpty {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(0..<metrics.perCoreUsage.count, id: \.self) { i in
                            let usage = metrics.perCoreUsage[i]
                            let coreColor: Color = usage >= 85.0 ? .red : (usage >= 60.0 ? .orange : .accentColor)
                            
                            VStack(spacing: 2) {
                                ZStack(alignment: .bottom) {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(height: 30)
                                    
                                    Rectangle()
                                        .fill(coreColor)
                                        .frame(height: 30 * CGFloat(max(0, usage) / 100.0))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                
                                Text("\(i+1)")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .frame(height: 40)
                }
                
                // REQ-022: CPU Temperature (if available)
                if let temp = metrics.temperature {
                    Text(String(format: "Temperature: %.1f°C", temp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Memory Card

struct MemoryCard: View {
    let metrics: RAMMetrics
    
    private var isCritical: Bool {
        metrics.usagePercent >= 88.0 // REQ-030
    }
    
    var body: some View {
        let titleColor: Color = isCritical ? .red : .primary // REQ-029, REQ-031
        
        CardContainer(title: "Memory", icon: "memorychip", value: String(format: "%.0f%%", metrics.usagePercent), valueColor: titleColor) {
            VStack(alignment: .leading, spacing: 8) {
                // REQ-027: App, Wired, Compressed
                MemoryRow(label: "App Memory", bytes: metrics.appMemoryBytes, color: .green)
                MemoryRow(label: "Wired Memory", bytes: metrics.wiredBytes, color: .red)
                MemoryRow(label: "Compressed", bytes: metrics.compressedBytes, color: .orange)
                
                // REQ-028: Swap (only if > 0)
                if metrics.swapUsedBytes > 0 {
                    MemoryRow(label: "Swap Used", bytes: metrics.swapUsedBytes, color: .gray)
                }
            }
            .font(.caption)
        }
    }
}

struct MemoryRow: View {
    let label: String
    let bytes: UInt64
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatBytes(bytes))
                .foregroundStyle(.primary)
                .font(.system(.caption, design: .monospaced))
        }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Disk Card

struct DiskCard: View {
    let metrics: DiskMetrics
    
    private var isCritical: Bool {
        metrics.usagePercent >= 90.0 // REQ-036
    }
    
    var body: some View {
        let titleColor: Color = isCritical ? .red : .primary // REQ-037
        
        CardContainer(title: "Macintosh HD", icon: "internaldrive", value: String(format: "%.0f%% Full", metrics.usagePercent), valueColor: titleColor) {
            VStack(alignment: .leading, spacing: 12) {
                // REQ-033: Free / Used GB
                HStack {
                    VStack(alignment: .leading) {
                        Text("Used")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f GB", metrics.usedGB))
                            .font(.system(.caption, design: .monospaced))
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Total")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f GB", metrics.totalGB))
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                
                // Storage Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                        Rectangle()
                            .fill(isCritical ? Color.red : Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(metrics.usagePercent / 100.0))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(height: 6)
                
                // REQ-035: Live I/O
                HStack {
                    Label(String(format: "R: %.1f MB/s", metrics.readBytesPerSec / 1_048_576.0), systemImage: "arrow.up.right")
                    Spacer()
                    Label(String(format: "W: %.1f MB/s", metrics.writeBytesPerSec / 1_048_576.0), systemImage: "arrow.down.right")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Network Card

struct NetworkCard: View {
    let metrics: NetworkMetrics
    
    var body: some View {
        let interfaceName = metrics.interfaceName ?? "Offline" // REQ-045
        
        CardContainer(title: "Network (\(interfaceName))", icon: "network", value: formatSpeed(metrics.combinedMBPerSec * 1_048_576.0)) {
            VStack(spacing: 12) {
                // REQ-039: Down / Up speeds (REQ-042 dynamic units)
                HStack {
                    NetworkSpeedRow(label: "Download", icon: "arrow.down.circle.fill", speedBytes: metrics.downloadBytesPerSec, color: .blue)
                    Spacer()
                    NetworkSpeedRow(label: "Upload", icon: "arrow.up.circle.fill", speedBytes: metrics.uploadBytesPerSec, color: .purple)
                }
                
                Divider()
                
                // REQ-040: Cumulative data
                HStack {
                    Text("Session Data:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("↓ \(formatData(metrics.totalDownloadedBytes))  ↑ \(formatData(metrics.totalUploadedBytes))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576.0 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        } else {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        }
    }
    
    private func formatData(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        return String(format: "%.0f KB", Double(bytes) / 1024.0)
    }
}

struct NetworkSpeedRow: View {
    let label: String
    let icon: String
    let speedBytes: Double
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formatSpeed(speedBytes))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
            }
        }
    }
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576.0 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576.0)
        } else {
            return String(format: "%.0f KB/s", bytesPerSec / 1024.0)
        }
    }
}

// MARK: - Card Container

struct CardContainer<Content: View>: View {
    let title: String
    let icon: String
    let value: String
    var valueColor: Color = .primary
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(value)
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .foregroundStyle(valueColor)
            }
            
            // Content
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        )
    }
}
