import AppKit
import SwiftUI

@main
struct DeskCatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { Text("DeskCat").padding() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menu.delegate = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "🐈"
        statusItem?.menu = menu
        rebuildMenu()
        AppleRemindersBridge.shared.start()

        let size = NSSize(width: 256, height: 176)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = CatDropView(frame: NSRect(origin: .zero, size: size))
        self.panel = panel
        if let x = UserDefaults.standard.object(forKey: "deskcat.x") as? Double,
           let y = UserDefaults.standard.object(forKey: "deskcat.y") as? Double {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            positionAtCorner()
        }
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(self, selector: #selector(savePosition),
            name: NSWindow.didMoveNotification, object: panel)
    }

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        Task { @MainActor [weak self] in self?.rebuildMenu() }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        for (title, selector) in [
            ("Show DeskCat", #selector(showCat)),
            ("Reset position", #selector(resetPosition)),
            ("Refresh Reminders", #selector(refreshReminders)),
            ("Open Reminders", #selector(openReminders)),
            ("Quit DeskCat", #selector(quit))
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        AppleRemindersBridge.shared.populateMenu(menu)
    }

    @objc private func refreshReminders() { AppleRemindersBridge.shared.refresh() }
    @objc private func openReminders() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
    }
    private func positionAtCorner() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 16,
                                     y: frame.minY + 16))
    }
    @objc private func resetPosition() { positionAtCorner(); panel?.orderFrontRegardless() }
    @objc private func savePosition() {
        guard let panel else { return }
        UserDefaults.standard.set(Double(panel.frame.minX), forKey: "deskcat.x")
        UserDefaults.standard.set(Double(panel.frame.minY), forKey: "deskcat.y")
    }
    @objc private func showCat() { panel?.orderFrontRegardless() }
    @objc private func quit() { NSApp.terminate(nil) }
}
