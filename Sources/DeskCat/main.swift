import AppKit
import SwiftUI

@main
struct DeskCatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            Text("DeskCat • v0.1 prototype")
                .padding()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show DeskCat", action: #selector(showCat), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit DeskCat", action: #selector(quit), keyEquivalent: "q"))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "🐈"
        statusItem?.menu = menu

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 230, height: 150),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = CatDropView(frame: panel.contentView?.bounds ?? .zero)
        self.panel = panel
        showCat()
    }

    @objc private func showCat() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 12,
                                     y: frame.minY + 12))
        panel.orderFrontRegardless()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
