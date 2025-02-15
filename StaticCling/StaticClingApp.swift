//
//  StaticClingApp.swift
//  StaticCling
//
//  Created by Alin Panaitiu on 03.02.2025.
//

import AppKit
import Combine
import Defaults
import EonilFSEvents
import Lowtech
import LowtechIndie
import Sparkle
import SwiftUI
import System

@MainActor
func cleanup() {
    FUZZY.cleanup()
}

@MainActor
class AppDelegate: LowtechIndieAppDelegate {
    static var shared: AppDelegate? { NSApp.delegate as? AppDelegate }

    var mainWindow: NSWindow? {
        NSApp.windows.first { $0.title == "StaticCling" }
    }
    var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.title.contains("Settings") }
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.disableRelaunchOnLogin()
        if !SWIFTUI_PREVIEW,
           let app = NSWorkspace.shared.runningApplications.first(where: {
               $0.bundleIdentifier == Bundle.main.bundleIdentifier
                   && $0.processIdentifier != NSRunningApplication.current.processIdentifier
           })
        {
            app.forceTerminate()
        }
        FUZZY.start()
        setupCleanup()

        super.applicationDidFinishLaunching(notification)

        KM.specialKey = .slash
        KM.specialKeyModifiers = [.rcmd]
        KM.onSpecialHotkey = { [self] in
            if let mainWindow, mainWindow.isKeyWindow {
                mainWindow.resignKey()
                mainWindow.resignMain()
                mainWindow.close()
                APP_MANAGER.lastFrontmostApp?.activate()
            } else {
                WM.open("main")
                focusWindow()
                focus()
            }
        }

        UM.updater = updateController.updater

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil
        )

        if Defaults[.showWindowAtLaunch] {
            WM.open("main")
            mainWindow?.becomeMain()
            mainWindow?.becomeKey()
            focus()
        } else {
            NSApp.setActivationPolicy(.accessory)
            mainWindow?.close()
        }
    }

    override func applicationDidBecomeActive(_ notification: Notification) {
        guard didBecomeActiveAtLeastOnce else {
            didBecomeActiveAtLeastOnce = true
            return
        }
//        log.debug("Became active")
        focusWindow()
    }

    override func applicationDidResignActive(_ notification: Notification) {
//        log.debug("Resigned active")
        mainWindow?.close()
    }

    func focusWindow() {
        mainAsyncAfter(0.1) {
            self.mainWindow?.makeKeyAndOrderFront(nil)
            self.mainWindow?.orderFrontRegardless()
            self.mainWindow?.becomeMain()
            self.mainWindow?.becomeKey()
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let oldpid = FileManager.default.contents(atPath: PIDFILE.string)?.s?.i32 else {
            return
        }
        log.debug("Killing old process: \(oldpid)")
        kill(oldpid, SIGKILL)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !SWIFTUI_PREVIEW else {
            return true
        }

//        log.debug("Reopened")

        if let mainWindow {
            mainWindow.orderFrontRegardless()
            mainWindow.becomeMain()
            mainWindow.becomeKey()
            focus()
        } else {
            WM.open("main")
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    func setupCleanup() {
        signal(SIGINT) { _ in
            cleanup()
            exit(0)
        }
        signal(SIGTERM) { _ in
            cleanup()
            exit(0)
        }
        signal(SIGKILL) { _ in
            cleanup()
            exit(0)
        }
    }

    @objc func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window.title == "StaticCling" {
            APP_MANAGER.lastFrontmostApp?.activate()
        }
    }
    @objc func windowDidBecomeMain(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window.title == "StaticCling" {
            window.titlebarAppearsTransparent = true
            window.styleMask = [
                .fullSizeContentView, .closable, .resizable, .miniaturizable, .titled,
                .nonactivatingPanel,
            ]
            window.isMovableByWindowBackground = true
        }
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        cleanup()
    }
}

class WindowManager: ObservableObject {
    @Published var windowToOpen: String? = nil

    func open(_ window: String) {
        windowToOpen = window
    }
}
let WM = WindowManager()

@main
struct StaticClingApp: App {
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismiss) var dismiss
    @ObservedObject var wm = WM

    var body: some Scene {
        Window("StaticCling", id: "main") {
            ContentView()
                .frame(minWidth: 1010, minHeight: 300)
                .ignoresSafeArea()
        }
        .defaultSize(width: 1010, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .help) {
                Button("Check for updates (current version: v\(Bundle.main.version))") {
                    UM.updater?.checkForUpdates()
                }
                .keyboardShortcut("U", modifiers: [.command])
            }
        }
        .onChange(of: wm.windowToOpen) {
            guard let window = wm.windowToOpen, !SWIFTUI_PREVIEW else {
                return
            }
            if window == "main", NSApp.windows.first(where: { $0.title == "StaticCling" }) != nil {
                focus()
                appDelegate.focusWindow()
                wm.windowToOpen = nil
                return
            }

            openWindow(id: window)
            focus()
            NSApp.keyWindow?.orderFrontRegardless()
            wm.windowToOpen = nil
        }

        Settings {
            SettingsView()
                .frame(minWidth: 600, minHeight: 600)
        }
        .defaultSize(width: 600, height: 600)
    }

    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

}
