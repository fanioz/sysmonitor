//
//  StatusBarFormatter.swift
//  sysmonitor
//
//  Formats system metrics into an NSAttributedString for the menu bar
//  status item, with color coding based on threshold levels.
//
//  Requirements: REQ-009, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014,
//                REQ-015, REQ-016, REQ-017
//

import AppKit

/// Design tokens from EARS.md for status bar color coding.
enum StatusBarThreshold {
    /// CPU warning threshold: 60% (REQ-013, REQ-025).
    static let cpuWarning: Double = 60.0
    /// CPU critical threshold: 85% (REQ-014, REQ-024).
    static let cpuCritical: Double = 85.0
    /// RAM critical threshold: 88% (REQ-015, REQ-030).
    static let ramCritical: Double = 88.0

    /// Amber warning color #FF9F0A (REQ-013).
    static let amberColor = NSColor(red: 1.0, green: 0.624, blue: 0.039, alpha: 1.0)
    /// Red critical color #FF453A (REQ-014).
    static let redColor = NSColor(red: 1.0, green: 0.271, blue: 0.227, alpha: 1.0)
}

/// Builds attributed strings for the menu bar status item.
enum StatusBarFormatter {

    /// Builds the full status bar attributed string from current metrics.
    ///
    /// Format: `CPU <n>% · RAM <n>%` with optional `⚠`, `↓<n>MB/s`, `SSD <n>%`
    ///
    /// - Parameters:
    ///   - metrics: Current system metrics snapshot.
    ///   - showNetwork: Whether to append download speed (REQ-016).
    ///   - showDisk: Whether to append disk usage (REQ-017).
    /// - Returns: Attributed string with color-coded CPU value.
    static func format(
        metrics: SystemMetrics,
        showNetwork: Bool = false,
        showDisk: Bool = false
    ) -> NSAttributedString {

        let result = NSMutableAttributedString()

        let defaultFont = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .medium
        )
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: defaultFont
        ]

        // -- CPU segment (REQ-011, REQ-012, REQ-013, REQ-014) --

        let cpuValue = Int(metrics.cpu.aggregateUsage.rounded())
        let cpuColor = colorForCPU(metrics.cpu.aggregateUsage)

        result.append(NSAttributedString(string: "CPU ", attributes: defaultAttrs))

        var cpuValueAttrs = defaultAttrs
        cpuValueAttrs[.foregroundColor] = cpuColor
        result.append(NSAttributedString(string: "\(cpuValue)%", attributes: cpuValueAttrs))

        // -- Separator --
        result.append(NSAttributedString(string: " · ", attributes: defaultAttrs))

        // -- RAM segment (REQ-011) --
        let ramValue = Int(metrics.ram.usagePercent.rounded())
        result.append(NSAttributedString(string: "RAM \(ramValue)%", attributes: defaultAttrs))

        // -- RAM warning indicator (REQ-015) --
        if metrics.ram.usagePercent >= StatusBarThreshold.ramCritical {
            var warningAttrs = defaultAttrs
            warningAttrs[.foregroundColor] = StatusBarThreshold.redColor
            result.append(NSAttributedString(string: " ⚠", attributes: warningAttrs))
        }

        // -- Optional: Network download speed (REQ-016) --
        if showNetwork {
            let dlSpeed = String(format: "%.1f", metrics.network.downloadMBPerSec)
            result.append(NSAttributedString(string: " · ↓\(dlSpeed)MB/s", attributes: defaultAttrs))
        }

        // -- Optional: Disk usage (REQ-017) --
        if showDisk {
            let diskValue = Int(metrics.disk.usagePercent.rounded())
            result.append(NSAttributedString(string: " · SSD \(diskValue)%", attributes: defaultAttrs))
        }

        return result
    }

    /// Returns the appropriate text color for the given CPU usage level.
    ///
    /// - `< 60%` → default system text color (REQ-012)
    /// - `60–84%` → amber #FF9F0A (REQ-013)
    /// - `≥ 85%` → red #FF453A (REQ-014)
    static func colorForCPU(_ usage: Double) -> NSColor {
        if usage >= StatusBarThreshold.cpuCritical {
            return StatusBarThreshold.redColor
        } else if usage >= StatusBarThreshold.cpuWarning {
            return StatusBarThreshold.amberColor
        } else {
            return .controlTextColor
        }
    }
}
