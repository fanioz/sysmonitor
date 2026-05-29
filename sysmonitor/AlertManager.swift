//
//  AlertManager.swift
//  sysmonitor
//
//  Manages system notifications and alert state for high metric thresholds.
//
//  Requirements: REQ-046, REQ-048, REQ-049, REQ-050
//

import Foundation
import UserNotifications
import Combine

/// Manages alert thresholds and local notifications.
final class AlertManager: ObservableObject {
    
    // MARK: - Thresholds (REQ-046)
    
    private let cpuCriticalThreshold = 85.0
    private let ramCriticalThreshold = 88.0
    private let diskCriticalThreshold = 92.0
    
    // MARK: - Rate Limiting (REQ-050)
    
    private var lastCPUNotificationTime: Date = .distantPast
    private var lastRAMNotificationTime: Date = .distantPast
    private var lastDiskNotificationTime: Date = .distantPast
    private let notificationCooldown: TimeInterval = 600 // 10 minutes
    
    // MARK: - Alert State
    
    @Published var activeAlerts: [AlertType] = []
    
    enum AlertType: Equatable {
        case cpu(value: Double)
        case ram(value: Double)
        case disk(value: Double)
        
        var message: String {
            switch self {
            case .cpu(let val): return String(format: "CPU Usage High: %.0f%%", val)
            case .ram(let val): return String(format: "Memory Usage High: %.0f%%", val)
            case .disk(let val): return String(format: "Disk Space Low: %.0f%% Full", val)
            }
        }
        
        // Custom equality to group alerts by type
        static func ==(lhs: AlertType, rhs: AlertType) -> Bool {
            switch (lhs, rhs) {
            case (.cpu, .cpu): return true
            case (.ram, .ram): return true
            case (.disk, .disk): return true
            default: return false
            }
        }
    }
    
    init() {
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("SysMonitor: Notifications authorized.")
            } else if let error = error {
                print("SysMonitor: Notification auth error: \(error)")
            }
        }
    }
    
    /// Evaluates the latest metrics against thresholds.
    func evaluateMetrics(_ metrics: SystemMetrics) {
        let now = Date()
        var currentAlerts: [AlertType] = []
        
        // 1. CPU
        if metrics.cpu.aggregateUsage >= cpuCriticalThreshold {
            currentAlerts.append(.cpu(value: metrics.cpu.aggregateUsage))
            
            if now.timeIntervalSince(lastCPUNotificationTime) >= notificationCooldown {
                sendNotification(title: "High CPU Usage", body: String(format: "CPU usage has reached %.0f%%.", metrics.cpu.aggregateUsage))
                lastCPUNotificationTime = now
            }
        }
        
        // 2. RAM
        if metrics.ram.usagePercent >= ramCriticalThreshold {
            currentAlerts.append(.ram(value: metrics.ram.usagePercent))
            
            if now.timeIntervalSince(lastRAMNotificationTime) >= notificationCooldown {
                sendNotification(title: "High Memory Usage", body: String(format: "Memory usage has reached %.0f%%.", metrics.ram.usagePercent))
                lastRAMNotificationTime = now
            }
        }
        
        // 3. Disk
        if metrics.disk.usagePercent >= diskCriticalThreshold {
            currentAlerts.append(.disk(value: metrics.disk.usagePercent))
            
            if now.timeIntervalSince(lastDiskNotificationTime) >= notificationCooldown {
                sendNotification(title: "Low Disk Space", body: String(format: "Disk is %.0f%% full.", metrics.disk.usagePercent))
                lastDiskNotificationTime = now
            }
        }
        
        // REQ-048: Hide alert banner when all metrics drop below thresholds
        // This is handled by updating activeAlerts (SwiftUI will rebuild)
        DispatchQueue.main.async {
            self.activeAlerts = currentAlerts
        }
    }
    
    /// REQ-049: Send UNUserNotification
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("SysMonitor: Failed to send notification: \(error)")
            }
        }
    }
}
