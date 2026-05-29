//
//  AlertBannerView.swift
//  sysmonitor
//
//  UI component for displaying critical threshold alerts.
//
//  Requirements: REQ-046, REQ-047, REQ-048
//

import SwiftUI

struct AlertBannerView: View {
    let alerts: [AlertManager.AlertType]
    
    // REQ-047: Animate pulsing red indicator (1.2s cycle)
    @State private var isPulsing = false
    
    var body: some View {
        if !alerts.isEmpty { // REQ-048: Hide when empty
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .opacity(isPulsing ? 1.0 : 0.3)
                        .animation(
                            Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                    
                    Text("CRITICAL ALERTS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.red)
                    
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(alerts, id: \.message) { alert in
                        Text("• " + alert.message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.leading, 18)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
            )
            .onAppear {
                isPulsing = true
            }
        }
    }
}
