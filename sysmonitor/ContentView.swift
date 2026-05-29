//
//  ContentView.swift
//  sysmonitor
//
//  Main widget content view with glass-morphism styling.
//  Provides the layout structure for header, metric cards, and footer.
//
//  Requirements: REQ-056, REQ-058, REQ-059, REQ-060, REQ-061, REQ-062
//

import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var store: MetricsStore
    @EnvironmentObject var alertManager: AlertManager

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle area (replaces hidden title bar).
            WindowDragBar()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // Header — machine info and clock (REQ-060, REQ-061).
                    HeaderView()
                    
                    // Alerts (REQ-046)
                    AlertBannerView(alerts: alertManager.activeAlerts)

                    // Metric cards (REQ-020, REQ-027, REQ-033, REQ-039)
                    CPUCard(metrics: store.current.cpu)
                    MemoryCard(metrics: store.current.ram)
                    DiskCard(metrics: store.current.disk)
                    NetworkCard(metrics: store.current.network)

                    // Footer — uptime (REQ-062).
                    FooterView()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .overlay {
                if store.current.cpu.aggregateUsage == 0 && store.current.ram.usagePercent == 0 {
                    // REQ-068: Loading spinner
                    VStack {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading Metrics...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                } else if store.current.isStale {
                    // REQ-066: Permission Required or System Error
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                        
                        Text("Permission Required")
                            .font(.headline)
                        
                        Text("SysMonitor needs system access to collect metrics.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Open System Settings") {
                            // Link to Privacy & Security settings
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.link)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 380, minHeight: 400, idealHeight: 560)
        // REQ-058: Semi-transparent glass surface over the NSVisualEffectView backdrop.
        .background(Color.black.opacity(0.001)) // Ensure hit-testing works.
    }
}

// MARK: - Window Drag Bar

/// A transparent drag region at the top of the window, replacing the hidden title bar.
/// Allows the user to drag the window while keeping the glass-morphism look.
struct WindowDragBar: View {
    var body: some View {
        Color.clear
            .frame(height: 28)
            .contentShape(Rectangle())
    }
}

// MARK: - Header (REQ-060, REQ-061)

struct HeaderView: View {
    /// Machine name from the system.
    private let machineName = Host.current().localizedName ?? "Mac"

    /// macOS version string.
    private let osVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }()

    /// CPU model string.
    private let cpuModel: String = {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &model, &size, nil, 0)
        let fullString = String(cString: model)
        // Shorten for display.
        return fullString
            .replacingOccurrences(of: "(R)", with: "")
            .replacingOccurrences(of: "(TM)", with: "")
            .trimmingCharacters(in: .whitespaces)
    }()

    /// Total RAM in GB.
    private let totalRAM: String = {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let gb = Double(bytes) / 1_073_741_824.0
        return String(format: "%.0f GB RAM", gb)
    }()

    /// Current time, updated every second.
    @State private var currentTime = Date()

    /// Timer to tick the clock every second.
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            // Machine info row.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(machineName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("\(osVersion) · \(totalRAM)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text(cpuModel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Real-time clock (REQ-061).
                VStack(alignment: .trailing, spacing: 2) {
                    Text(currentTime, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                        .font(.system(size: 22, weight: .light, design: .monospaced))
                        .foregroundStyle(.primary)

                    Text(currentTime, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
        .onReceive(clockTimer) { time in
            currentTime = time
        }
    }
}

// MARK: - Footer (REQ-062)

struct FooterView: View {
    /// System uptime formatted as `<d>d <h>h <m>m`.
    private var uptimeString: String {
        let uptime = ProcessInfo.processInfo.systemUptime
        let days = Int(uptime) / 86400
        let hours = (Int(uptime) % 86400) / 3600
        let minutes = (Int(uptime) % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }

    var body: some View {
        HStack {
            Label("Uptime: \(uptimeString)", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Text("SysMonitor v1.0")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(MetricsStore())
        .environmentObject(AlertManager())
        .frame(width: 380, height: 560)
        .background(.ultraThinMaterial)
}
