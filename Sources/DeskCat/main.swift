import AppKit
import SwiftUI

@main
struct DeskCatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { Text("DeskCat · Pixel prototype").padding() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show DeskCat", action: #selector(showCat), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reset position", action: #selector(resetPosition), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit DeskCat", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "🐈"
        statusItem?.menu = menu

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 290, height: 185),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = CatDropView(frame: NSRect(x: 0, y: 0, width: 290, height: 185))
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
