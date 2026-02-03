import SwiftUI
import AppKit

/// App delegate - manages NSStatusItem and NSWindow
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var hookSetupWindow: NSWindow?
    private var coordinator: WatchCoordinator?
    private var titlebarAccessory: NSTitlebarAccessoryViewController?
    private var titlebarStatusView: NSHostingView<TitlebarStatusView>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create WatchCoordinator
        coordinator = WatchCoordinator()

        // Setup menu bar item
        setupStatusItem()

        // Setup main window
        setupMainWindow()

        // Setup notification observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showHookSetup),
            name: .showHookSetup,
            object: nil
        )

        // Start monitoring
        coordinator?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Default icon setup
            button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Claude Watch")

            // Receive both left-click and right-click events
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleStatusItemClick)
            button.target = self
        }

        // Setup status observer
        setupStatusObserver()
    }

    private func setupMainWindow() {
        guard let coordinator = coordinator else { return }

        let contentView = DropdownPanel(coordinator: coordinator) { [weak self] in
            self?.quitApp()
        }

        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        mainWindow?.contentView = NSHostingView(rootView: contentView)
        mainWindow?.title = "Claude Watch"
        mainWindow?.isReleasedWhenClosed = false  // Don't release when closed
        mainWindow?.isOpaque = false
        mainWindow?.backgroundColor = .clear
        mainWindow?.titlebarAppearsTransparent = true
        mainWindow?.styleMask.insert(.fullSizeContentView)
        mainWindow?.setFrameAutosaveName("MainWindow")  // Remember position
        mainWindow?.minSize = NSSize(width: 320, height: 300)
        mainWindow?.center()

        // Add titlebar accessory for status indicator
        setupTitlebarAccessory()
    }

    private func setupTitlebarAccessory() {
        guard let coordinator = coordinator, let window = mainWindow else { return }

        let statusView = TitlebarStatusView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: statusView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 100, height: 22)

        titlebarStatusView = hostingView

        let accessoryVC = NSTitlebarAccessoryViewController()
        accessoryVC.view = hostingView
        accessoryVC.layoutAttribute = .trailing

        window.addTitlebarAccessoryViewController(accessoryVC)
        titlebarAccessory = accessoryVC
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleWindow()
        }
    }

    @objc private func toggleWindow() {
        guard let window = mainWindow else { return }

        if window.isVisible && window.isKeyWindow {
            // Already visible and in front, so hide
            window.close()
        } else {
            // Not visible or not in front, bring to front
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let showHideTitle = mainWindow?.isVisible == true ? "Hide Window" : "Show Window"
        let showHideItem = NSMenuItem(title: showHideTitle, action: #selector(toggleWindow), keyEquivalent: "")
        showHideItem.target = self
        menu.addItem(showHideItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About Claude Watch", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Claude Watch", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Show menu
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil  // Remove menu for next left-click
    }

    private func setupStatusObserver() {
        // Check status with timer (simple implementation)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  let button = self.statusItem?.button else { return }
            self.updateStatusButton(button)
        }
    }

    private func updateStatusButton(_ button: NSStatusBarButton) {
        guard let coordinator = coordinator else { return }

        let watchState = coordinator.watchState
        let activeCount = coordinator.totalActiveSubagents

        // Create icon image
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let iconName = watchState == .stopped ? "circle" : "circle.fill"

        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Claude Watch") {
            let configuredImage = image.withSymbolConfiguration(config)

            // Apply color
            let color: NSColor
            switch watchState {
            case .stopped, .watching:
                color = NSColor.secondaryLabelColor
            case .active:
                color = NSColor.systemBlue
            }

            if let tintedImage = configuredImage?.tinted(with: color) {
                button.image = tintedImage
            }
        }

        // Badge text
        if activeCount > 0 {
            button.title = "\(activeCount)"
        } else {
            button.title = ""
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let hostingView = NSHostingView(rootView: SettingsView())
            hostingView.setFrameSize(hostingView.fittingSize)

            settingsWindow = NSWindow(
                contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.contentView = hostingView
            settingsWindow?.title = "Settings"
            settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.level = .floating
            settingsWindow?.center()
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        if aboutWindow == nil {
            aboutWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            aboutWindow?.contentView = NSHostingView(rootView: AboutView())
            aboutWindow?.title = "About Claude Watch"
            aboutWindow?.isReleasedWhenClosed = false
            aboutWindow?.level = .floating
            aboutWindow?.center()
        }

        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showHookSetup() {
        if hookSetupWindow == nil {
            hookSetupWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 620),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            hookSetupWindow?.contentView = NSHostingView(rootView: HookSetupView())
            hookSetupWindow?.title = "Hook Setup Guide"
            hookSetupWindow?.isReleasedWhenClosed = false
            hookSetupWindow?.level = .floating
            hookSetupWindow?.center()
        }

        hookSetupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - NSImage Extension
extension NSImage {
    func tinted(with color: NSColor) -> NSImage? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let size = self.size
        let rect = NSRect(origin: .zero, size: size)

        let newImage = NSImage(size: size)
        newImage.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            context.clip(to: rect, mask: cgImage)
            color.setFill()
            context.fill(rect)
        }

        newImage.unlockFocus()
        newImage.isTemplate = false

        return newImage
    }
}
