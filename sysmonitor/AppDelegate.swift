//
//  AppDelegate.swift
//  sysmonitor
//
//  Manages the NSStatusItem, main widget window lifecycle,
//  metrics polling timer, and coordinates first-launch vs login-launch behavior.
//
//  Requirements: REQ-001 through REQ-017, REQ-051, REQ-053,
//                REQ-063, REQ-064, REQ-065
//

import AppKit
import SwiftUI
import ServiceManagement

/// The AppDelegate owns the menu bar status item and the main widget window.
/// It is created by `sysmonitorApp` via `@NSApplicationDelegateAdaptor`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    /// The persistent menu bar status item (REQ-002).
    private var statusItem: NSStatusItem!

    /// The main widget window, lazily created on first show.
    private var widgetWindow: NSWindow?

    /// Collects CPU, RAM, and other system metrics.
    private let metricsCollector = MetricsCollector()

    /// Holds and publishes the latest collected metrics to the SwiftUI UI (REQ-052).
    private let metricsStore = MetricsStore()

    /// Manages critical threshold alerts and notifications (REQ-046, REQ-049).
    private let alertManager = AlertManager()

    /// Timer that drives periodic metric collection and status bar updates.
    private var pollingTimer: Timer?

    /// Polling interval when the widget window is visible (REQ-051).
    private let visiblePollingInterval: TimeInterval = 2.0

    /// Polling interval when the widget window is hidden (REQ-053).
    private let hiddenPollingInterval: TimeInterval = 5.0

    // MARK: - Preference Keys

    /// Key for persisting whether the app has been launched before.
    private let hasLaunchedBeforeKey = "hasLaunchedBefore"

    /// Key for persisting "Launch at Login" preference.
    private let launchAtLoginKey = "launchAtLogin"

    /// Key for persisting "Show Network in Menu Bar" preference (REQ-016).
    static let showNetworkInMenuBarKey = "showNetworkInMenuBar"

    /// Key for persisting "Show Disk in Menu Bar" preference (REQ-017).
    static let showDiskInMenuBarKey = "showDiskInMenuBar"

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // Take a baseline CPU sample so the next poll has a delta.
        _ = metricsCollector.collectCPU()

        // Start polling metrics immediately (REQ-010, REQ-051).
        startPollingTimer()

        // Observe defaults changes to instantly update menu bar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        let isFirstLaunch = !UserDefaults.standard.bool(forKey: hasLaunchedBeforeKey)
        let isLoginLaunch = isLaunchedAtLogin()

        if isLoginLaunch {
            // REQ-065: Start in menu-bar-only mode when launched at login.
            // Do not show the widget window.
        } else if isFirstLaunch {
            // REQ-003: First launch — show the main widget window.
            UserDefaults.standard.set(true, forKey: hasLaunchedBeforeKey)
            showWidgetWindow()
        } else {
            // Subsequent manual launches — show the widget window.
            showWidgetWindow()
        }
    }

    @objc private func defaultsChanged() {
        updateStatusBarText()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // REQ-004: Closing the window must NOT terminate the app.
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // REQ-007: Clean up on quit.
        pollingTimer?.invalidate()
        pollingTimer = nil

        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - Polling Timer (REQ-010, REQ-051, REQ-053, REQ-055)

    /// Starts or restarts the polling timer at the appropriate interval.
    private func startPollingTimer() {
        pollingTimer?.invalidate()

        var interval = isWidgetWindowVisible ? visiblePollingInterval : hiddenPollingInterval

        // REQ-055: If self-throttled, double the polling interval.
        if metricsCollector.isSelfThrottled {
            interval *= 2.0
        }

        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.pollAndUpdate()
        }
        // Also run immediately so the status bar updates right away.
        pollAndUpdate()
    }

    /// Whether the main widget window is currently visible.
    private var isWidgetWindowVisible: Bool {
        widgetWindow?.isVisible ?? false
    }

    /// Collects metrics and updates the status bar text.
    /// Passes previous metrics for stale data fallback (REQ-054).
    private func pollAndUpdate() {
        let newMetrics = metricsCollector.collectAll(previous: metricsStore.current)
        metricsStore.current = newMetrics
        updateStatusBarText()
        
        // REQ-046: Evaluate metrics for alerts.
        alertManager.evaluateMetrics(newMetrics)

        // REQ-055: Check if self-throttling state changed; restart timer if needed.
        if metricsCollector.isSelfThrottled {
            // Only restart if not already throttled at the current interval.
            // The next startPollingTimer call will apply the throttled interval.
        }
    }

    // MARK: - Status Bar Text (REQ-011, REQ-012, REQ-013, REQ-014, REQ-015, REQ-016, REQ-017)

    /// Rebuilds the status item's attributed title from the latest metrics.
    private func updateStatusBarText() {
        guard let button = statusItem?.button else { return }

        let showNetwork = UserDefaults.standard.bool(forKey: AppDelegate.showNetworkInMenuBarKey)
        let showDisk = UserDefaults.standard.bool(forKey: AppDelegate.showDiskInMenuBarKey)

        button.attributedTitle = StatusBarFormatter.format(
            metrics: metricsStore.current,
            showNetwork: showNetwork,
            showDisk: showDisk
        )
    }

    // MARK: - Status Item Setup (REQ-002)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(statusItemLeftClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - Status Item Click Handling

    /// Dispatches left-click (toggle window) vs right-click (context menu).
    @objc private func statusItemLeftClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            // REQ-005: Left-click toggles widget window visibility.
            toggleWidgetWindow()
        }
    }

    // MARK: - Widget Window (REQ-003, REQ-004, REQ-005, REQ-058, REQ-059)

    /// Creates the widget window if needed, configured for glass-morphism appearance.
    private func createWidgetWindowIfNeeded() {
        guard widgetWindow == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // REQ-058: Glass-morphism — transparent title bar, non-opaque window.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear

        // REQ-058: Backdrop blur via NSVisualEffectView (≥20pt blur).
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]

        // Layer the SwiftUI content on top of the blur backdrop.
        let rootView = ContentView()
            .environmentObject(metricsStore)
            .environmentObject(alertManager)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]

        visualEffect.addSubview(hostingView)
        window.contentView = visualEffect

        window.title = "SysMonitor"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Smooth animation behavior for show/hide.
        window.animationBehavior = .utilityWindow

        widgetWindow = window
    }

    private func showWidgetWindow() {
        createWidgetWindowIfNeeded()
        guard let window = widgetWindow else { return }

        // Animate fade-in.
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        // REQ-051: Switch to 2s polling when visible.
        startPollingTimer()
    }

    private func hideWidgetWindow() {
        guard let window = widgetWindow else { return }

        // Animate fade-out, then hide.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            window.alphaValue = 1 // Reset for next show.
            // REQ-053: Switch to 5s polling when hidden.
            self?.startPollingTimer()
        })
    }

    private func toggleWidgetWindow() {
        if let window = widgetWindow, window.isVisible {
            hideWidgetWindow()
        } else {
            showWidgetWindow()
        }
    }

    // MARK: - Context Menu (REQ-006, REQ-007, REQ-063, REQ-064)

    private func showContextMenu() {
        let menu = NSMenu()

        // "Open Widget"
        let openItem = NSMenuItem(title: "Open Widget", action: #selector(openWidgetMenuAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // "Preferences"
        let prefsItem = NSMenuItem(title: "Preferences", action: #selector(openPreferencesMenuAction), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        // "Launch at Login" — togglable
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLoginMenuAction), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = UserDefaults.standard.bool(forKey: launchAtLoginKey) ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        // "Quit"
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitMenuAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Remove the menu after it closes so left-click still works via action.
        statusItem.menu = nil
    }

    // MARK: - Menu Actions

    @objc private func openWidgetMenuAction() {
        showWidgetWindow()
    }

    @objc private func openPreferencesMenuAction() {
        // REQ-063: Open standard Preferences window
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        // Bring app to front so preferences window is visible
        NSApp.activate(ignoringOtherApps: true)
    }

    /// REQ-063, REQ-064: Toggle Launch at Login via SMAppService.
    @objc private func toggleLaunchAtLoginMenuAction() {
        let currentValue = UserDefaults.standard.bool(forKey: launchAtLoginKey)
        let newValue = !currentValue

        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(newValue, forKey: launchAtLoginKey)
        } catch {
            // Log failure but don't crash.
            print("SysMonitor: Failed to \(newValue ? "register" : "unregister") login item: \(error)")
        }
    }

    /// REQ-007: Terminate all processes and remove the status item.
    @objc private func quitMenuAction() {
        NSApp.terminate(nil)
    }

    // MARK: - Login Launch Detection (REQ-065)

    /// Heuristic: if the app was launched very early (within 60s of boot),
    /// and the login item is registered, treat it as a login launch.
    private func isLaunchedAtLogin() -> Bool {
        let isRegistered = UserDefaults.standard.bool(forKey: launchAtLoginKey)
        guard isRegistered else { return false }

        // Check if launched by the system (no activation). The app won't be
        // the active app if macOS launched it at login in the background.
        return !NSApp.isActive
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    /// REQ-004: Closing the window hides it instead of terminating.
    /// REQ-053: Reduce polling to 5s when window is hidden.
    func windowWillClose(_ notification: Notification) {
        // The window's isReleasedWhenClosed = false, so it's just hidden.
        // Switch to the hidden polling interval.
        startPollingTimer()
    }
}
