import AppKit

/// Pixel-art desk, cat and trash. Entire illustration is rendered locally, without emoji or image assets.
@MainActor
final class CatDropView: NSView {
    private let trashService = TrashService()
    private let machine = CatStateMachine()
    private var isProcessing = false
    private var frameIndex = 0
    private var timer: Timer?
    private var dragOrigin: NSPoint?
    private var message = ""
    private var messageUntil = Date.distantPast

    private let catRect = NSRect(x: 44, y: 39, width: 108, height: 116)
    private let binRect = NSRect(x: 224, y: 42, width: 49, height: 64)
    private let deskRect = NSRect(x: 22, y: 15, width: 185, height: 43)

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        machine.onChange = { [weak self] _ in self?.needsDisplay = true }
        timer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.frameIndex += 1
                self.needsDisplay = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    deinit { timer?.invalidate() }
    override var isFlipped: Bool { false }

    private func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
        color.setFill()
        NSRect(x: x, y: y, width: w, height: h).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let ink = NSColor(calibratedRed: 0.17, green: 0.105, blue: 0.12, alpha: 1)
        let orange = NSColor(calibratedRed: 0.92, green: 0.56, blue: 0.28, alpha: 1)
        let light = NSColor(calibratedRed: 1, green: 0.85, blue: 0.67, alpha: 1)
        let brown = NSColor(calibratedRed: 0.43, green: 0.27, blue: 0.18, alpha: 1)
        let steel = NSColor(calibratedRed: 0.53, green: 0.60, blue: 0.67, alpha: 1)
        let step: CGFloat = 5

        // Wooden desk and small monitor.
        block(20, 28, 187, 40, ink)
        block(25, 33, 177, 30, brown)
        block(20, 63, 187, 9, ink)
        block(25, 66, 177, 4, NSColor(calibratedRed: 0.67, green: 0.45, blue: 0.29, alpha: 1))
        block(167, 79, 52, 50, ink)
        block(173, 85, 40, 37, NSColor(calibratedRed: 0.18, green: 0.13, blue: 0.23, alpha: 1))
        block(189, 71, 9, 10, ink)
        block(179, 68, 29, 5, ink)

        // Bin: dedicated destructive drop target.
        block(227, 44, 42, 44, ink)
        block(232, 49, 32, 35, steel)
        block(223, 87, 50, 7, ink)
        block(230, 90, 36, 4, NSColor.white.withAlphaComponent(0.65))
        for x in stride(from: 238, through: 258, by: 10) { block(CGFloat(x), 55, 3, 24, ink.withAlphaComponent(0.3)) }

        // Cat pixels in a stable logical 20x20 grid.
        let tailOffset: CGFloat = frameIndex % 12 < 6 ? 0 : 5
        block(43, 86 + tailOffset, 15, 11, ink)
        block(39, 78 + tailOffset, 10, 14, orange)
        let pixels: [String] = [
            "....OO......OO....",
            "...OXXO....OXXO...",
            "..OXXXXOOOOXXXXO..",
            "..OXXXXXXXXXXXXO..",
            ".OXXXXXXXXXXXXXXO.",
            ".OXXXXXXXXXXXXXXO.",
            "OXXXXKXXXXXXKXXXXO",
            "OXXXXXXXXXXXXXXXXO",
            "OXXXXXXKKXXXXXXXXO",
            "OXXXXLLLLLLXXXXXXO",
            ".OXXLLLLLLLLXXXXO.",
            ".OXXLLLLLLLLXXXXO.",
            "..OLLLLLLLLLLXXO..",
            "..OLLLLLLLLLLXXO..",
            "...OLLLLLLLLXXO...",
            "...OXXXXXXXXXXO....",
            "...OXXXXXXXXXXO....",
            "....OOOOOOOOOO....."
        ]
        let sleepy = machine.state == .idle && frameIndex % 110 > 82
        let blink = frameIndex % 39 == 0 || sleepy
        let walking = machine.state == .carry || machine.state == .walk || machine.state == .throwing
        let offset: CGFloat = walking ? CGFloat(min(frameIndex % 9, 5)) * 5 : 0
        let bounce: CGFloat = machine.state == .happy && frameIndex % 6 < 3 ? 10 : 0
        for (row, line) in pixels.enumerated() {
            for (column, ch) in line.enumerated() {
                let c: NSColor?
                switch ch {
                case "O": c = ink
                case "X": c = orange
                case "L": c = light
                case "K": c = blink ? orange : ink
                default: c = nil
                }
                if let c {
                    block(47 + CGFloat(column) * step + offset,
                          70 + CGFloat(pixels.count - row) * step + bounce,
                          step, step, c)
                }
            }
        }
        if machine.state == .happy {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 21)]
            ("✦" as NSString).draw(at: NSPoint(x: 148, y: 151), withAttributes: attributes)
        }
        if machine.state == .carry || machine.state == .throwing {
            block(142 + offset, 106, 22, 25, ink)
            block(146 + offset, 111, 15, 17, NSColor.white)
        }
        if Date() < messageUntil {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            (message as NSString).draw(at: NSPoint(x: 30, y: 1), withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragOrigin = event.locationInWindow
        if catRect.contains(point) {
            showActions(at: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragOrigin, let window else { return }
        let current = event.locationInWindow
        let dx = current.x - start.x
        let dy = current.y - start.y
        if abs(dx) + abs(dy) > 2 {
            window.setFrameOrigin(NSPoint(x: window.frame.origin.x + dx,
                                          y: window.frame.origin.y + dy))
        }
    }
    override func mouseUp(with event: NSEvent) { dragOrigin = nil }

    private func showActions(at point: NSPoint) {
        let menu = NSMenu()
        let tasks = NSMenuItem(title: "Quick task (coming soon)", action: nil, keyEquivalent: "")
        tasks.isEnabled = false
        menu.addItem(tasks)
        menu.addItem(NSMenuItem(title: "Open Calendar", action: #selector(openCalendar), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Downloads", action: #selector(openDownloads), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Clipboard Text", action: #selector(showClipboard), keyEquivalent: ""))
        for item in menu.items { item.target = self }
        menu.popUp(positioning: nil, at: point, in: self)
    }

    @objc private func openCalendar() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
    @objc private func openDownloads() {
        NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
    }
    @objc private func showClipboard() {
        let value = NSPasteboard.general.string(forType: .string) ?? "No text on clipboard"
        let alert = NSAlert()
        alert.messageText = "Clipboard (current text only)"
        alert.informativeText = String(value.prefix(500))
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func urls(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    private func onBin(_ sender: NSDraggingInfo) -> Bool {
        binRect.insetBy(dx: -8, dy: -8).contains(convert(sender.draggingLocation, from: nil))
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isProcessing, !urls(sender).isEmpty, onBin(sender) else { return [] }
        if machine.state != .alert { machine.transition(to: .alert) }
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        if !isProcessing { machine.transition(to: .idle) }
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !isProcessing, onBin(sender) else { return false }
        let files = urls(sender)
        guard !files.isEmpty else { return false }
        let alert = NSAlert()
        alert.messageText = "Move to macOS Trash?"
        alert.informativeText = "Move \(files.count) item(s) to Trash? This is not permanent deletion."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            machine.transition(to: .idle)
            return false
        }
        isProcessing = true
        machine.transition(to: .carry)
        let service = trashService
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let failures = files.compactMap { url -> String? in
                switch service.moveToTrash(url) {
                case .success: return nil
                case .failure(let error): return error.localizedDescription
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isProcessing = false
                if failures.isEmpty {
                    self.machine.transition(to: .throwing)
                    self.message = "Moved to Trash ✨"
                    self.messageUntil = Date().addingTimeInterval(2.5)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                        self?.machine.transition(to: .happy, resetAfter: 1.5)
                    }
                } else {
                    self.machine.transition(to: .error, resetAfter: 2)
                    let alert = NSAlert()
                    alert.messageText = "Some items could not be moved"
                    alert.informativeText = failures.joined(separator: "\n")
                    alert.runModal()
                }
                self.needsDisplay = true
            }
        }
        return true
    }
}
