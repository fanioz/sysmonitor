//
//  MetricsStore.swift
//  sysmonitor
//
//  Observable object that holds the latest system metrics for the SwiftUI UI.
//
//  Requirements: REQ-052
//

import Combine
import Foundation

/// Holds the latest system metrics and publishes them to the SwiftUI UI.
final class MetricsStore: ObservableObject {
    @Published var current: SystemMetrics = SystemMetrics()
}
