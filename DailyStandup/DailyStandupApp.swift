import SwiftUI
import ServiceManagement

@main
struct DailyStandupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "mic.circle.fill")
        }
    }
}

// MARK: - Menu Bar

struct MenuBarContent: View {
    var body: some View {
        Button("Start Standup") {
            WindowManager.shared.showStandup()
        }
        .keyboardShortcut("s")

        Button("Show Daily To-Do") {
            WindowManager.shared.showTodos()
        }
        .keyboardShortcut("t")

        Button("Planning (Beta)") {
            WindowManager.shared.showPlanning()
        }
        .keyboardShortcut("p")

        Divider()

        Button("Setup...") {
            WindowManager.shared.showSetup()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Daily Standup") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppState.shared.settings.launchAtLogin {
            try? SMAppService.mainApp.register()
        }

        // Start the standup timer
        NotificationManager.shared.start()

        // Process daily todos in background on launch
        TodoCache.shared.refreshIfNeeded()

        // Re-process on wake from sleep (new day check)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        if !AppState.shared.isConfigured {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                WindowManager.shared.showSetup()
            }
        }
    }

    @objc private func handleWake() {
        TodoCache.shared.refreshIfNeeded()
    }
}

// MARK: - Window Manager

class WindowManager {
    static let shared = WindowManager()
    private var standupWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var todoWindow: NSWindow?
    private var planningWindow: NSWindow?

    func showStandup() {
        let view = StandupView()
        let hostingView = NSHostingView(rootView: view)

        if standupWindow == nil {
            standupWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            standupWindow?.titlebarAppearsTransparent = true
            standupWindow?.titleVisibility = .hidden
            standupWindow?.isReleasedWhenClosed = false
            standupWindow?.setFrameAutosaveName("StandupWindow")
            standupWindow?.backgroundColor = .clear
            standupWindow?.isMovableByWindowBackground = true
        }
        standupWindow?.contentView = hostingView
        standupWindow?.center()
        standupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSetup() {
        let view = SetupView()
        let hostingView = NSHostingView(rootView: view)

        if setupWindow == nil {
            setupWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            setupWindow?.titlebarAppearsTransparent = true
            setupWindow?.titleVisibility = .hidden
            setupWindow?.isReleasedWhenClosed = false
            setupWindow?.backgroundColor = .clear
            setupWindow?.isMovableByWindowBackground = true
        }
        setupWindow?.contentView = hostingView
        setupWindow?.center()
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showTodos() {
        let view = TodoView()
        let hostingView = NSHostingView(rootView: view)

        if todoWindow == nil {
            todoWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            todoWindow?.titlebarAppearsTransparent = true
            todoWindow?.titleVisibility = .hidden
            todoWindow?.isReleasedWhenClosed = false
            todoWindow?.setFrameAutosaveName("TodoWindow")
            todoWindow?.backgroundColor = .clear
            todoWindow?.isMovableByWindowBackground = true
        }
        todoWindow?.contentView = hostingView
        todoWindow?.center()
        todoWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showPlanning() {
        let view = PlanningView()
        let hostingView = NSHostingView(rootView: view)

        if planningWindow == nil {
            planningWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            planningWindow?.titlebarAppearsTransparent = true
            planningWindow?.titleVisibility = .hidden
            planningWindow?.isReleasedWhenClosed = false
            planningWindow?.backgroundColor = .clear
            planningWindow?.isMovableByWindowBackground = true
        }
        planningWindow?.contentView = hostingView
        planningWindow?.center()
        planningWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
