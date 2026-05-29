//
//  PreferencesView.swift
//  sysmonitor
//
//  Standard preferences window for managing app settings.
//
//  Requirements: REQ-016, REQ-017, REQ-063, REQ-064
//

import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    // REQ-016: Show Network in Menu Bar
    @AppStorage(AppDelegate.showNetworkInMenuBarKey) private var showNetworkInMenuBar: Bool = false
    
    // REQ-017: Show Disk in Menu Bar
    @AppStorage(AppDelegate.showDiskInMenuBarKey) private var showDiskInMenuBar: Bool = false
    
    // REQ-063, REQ-064: Launch at Login
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    
    var body: some View {
        Form {
            Section(header: Text("Menu Bar Layout").font(.headline)) {
                Toggle("Show Network speed (↓MB/s)", isOn: $showNetworkInMenuBar)
                Toggle("Show Disk usage (SSD %)", isOn: $showDiskInMenuBar)
            }
            .padding(.bottom, 16)
            
            Section(header: Text("System").font(.headline)) {
                Toggle("Launch at Login", isOn: Binding<Bool>(
                    get: { launchAtLogin },
                    set: { newValue in
                        toggleLaunchAtLogin(newValue)
                    }
                ))
            }
        }
        .padding(24)
        .frame(width: 380, height: 200)
    }
    
    private func toggleLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enable
        } catch {
            print("SysMonitor: Failed to \(enable ? "register" : "unregister") login item: \(error)")
            // Revert on failure
            launchAtLogin = !enable
        }
    }
}
