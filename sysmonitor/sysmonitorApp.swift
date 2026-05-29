//
//  sysmonitorApp.swift
//  sysmonitor
//
//  Entry point for the SysMonitor app.
//  Delegates all lifecycle management to AppDelegate.
//
//  The app runs as a status bar agent (LSUIElement = YES) and uses
//  AppDelegate to manage the NSStatusItem and widget window.
//

import SwiftUI

@main
struct sysmonitorApp: App {
    /// Bridge to AppKit's NSApplicationDelegate for status bar and window management.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No default WindowGroup — the widget window is managed by AppDelegate.
        // This prevents SwiftUI from auto-creating a window on launch.
        Settings {
            PreferencesView()
        }
    }
}
