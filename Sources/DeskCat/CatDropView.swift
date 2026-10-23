import AppKit

/// Compact transparent pixel workstation. Drag anywhere except the Trash drop target
/// to reposition; clicking the cat (without moving) opens quick actions.
@MainActor
final class CatDropView: NSView {
    private let trashService = TrashService()
    private let machine = CatStateMachine()
    private var timer: Timer?
    private var tick = 0
    private var dragStartScreen: NSPoint?
    private var windowStart: NSPoint?
    private var dragged = false
    private var isProcessing = false

    private let catHit = NSRect(x: 124, y: 61, width: 75, height: 93)
    private let binHit = NSRect(x: 207, y: 8, width: 49, height: 59)
    override var isFlipped: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        machine.onChange = { [weak self] _ in self?.needsDisplay = true }
        timer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick += 1
                self.needsDisplay = true
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    deinit { timer?.invalidate() }

    private let outline = NSColor(calibratedWhite: 0.12, alpha: 1)
    private let cream = NSColor(calibratedRed: 0.99, green: 0.96, blue: 0.86, alpha: 1)
    private let ginger = NSColor(calibratedRed: 0.96, green: 0.64, blue: 0.35, alpha: 1)
    private let grey = NSColor(calibratedRed: 0.43, green: 0.44, blue: 0.47, alpha: 1)
    private let wood = NSColor(calibratedRed: 0.83, green: 0.59, blue: 0.37, alpha: 1)

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
        color.setFill()
        NSRect(x: x, y: y, width: w, height: h).fill()
    }
    private func poly(_ points: [NSPoint], _ color: NSColor) {
        guard let first = points.first else { return }
        let p = NSBezierPath()
        p.move(to: first)
        for point in points.dropFirst() { p.line(to: point) }
        p.close()
        color.setFill()
        p.fill()
    }
    private func shape(_ x: CGFloat, _ y: CGFloat, _ pixels: [String], _ scale: CGFloat,
                       _ palette: [Character: NSColor]) {
        for (row, line) in pixels.enumerated() {
            for (col, char) in line.enumerated() {
                if let color = palette[char] {
                    rect(x + CGFloat(col) * scale,
                         y + CGFloat(pixels.count - row - 1) * scale,
                         scale, scale, color)
                }
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // The entire view stays transparent. Only the workstation is drawn.
        let shadow = NSColor.black.withAlphaComponent(0.13)
        poly([NSPoint(x: 15,y: 17), NSPoint(x: 235,y: 17),
              NSPoint(x: 258,y: 7), NSPoint(x: 35,y: 7)], shadow)

        // Four separate wooden legs, including the two rear legs.
        rect(49, 23, 7, 41, outline)
        rect(51, 25, 4, 37, wood)
        rect(208, 20, 8, 46, outline)
        rect(210, 23, 4, 40, wood)
        rect(24, 16, 9, 49, outline)
        rect(27, 18, 5, 45, wood)
        rect(187, 11, 10, 52, outline)
        rect(190, 14, 6, 47, wood)

        // Isometric wooden desktop with dark edge.
        poly([NSPoint(x: 18,y: 70), NSPoint(x: 191,y: 70),
              NSPoint(x: 221,y: 57), NSPoint(x: 43,y: 57)], outline)
        poly([NSPoint(x: 22,y: 71), NSPoint(x: 189,y: 71),
              NSPoint(x: 216,y: 61), NSPoint(x: 44,y: 61)], wood)
        poly([NSPoint(x: 43,y: 61), NSPoint(x: 216,y: 61),
              NSPoint(x: 216,y: 56), NSPoint(x: 43,y: 56)], NSColor(calibratedRed: 0.55, green: 0.34, blue: 0.22, alpha: 1))

        // Brown chair behind the cat.
        rect(180, 88, 27, 57, outline)
        rect(184, 91, 19, 50, NSColor(calibratedRed: 0.52, green: 0.32, blue: 0.22, alpha: 1))

        // Calico cat, with tiny blinking and paw-typing animations.
        let cat: [String] = [
            ".....GG.......OO.....",
            "....GgGG.....OoOO....",
            "...GgggGG...OooOO....",
            "..GgggggGWWOoooOO...",
            "..GgggWWWWWOoooOO...",
            ".GGgWWWWWWWOoooOO...",
            ".GgWWWWWWWWWOooOO...",
            ".GgWWKWWWWKWWOOO....",
            ".GGWWWWPWWWWWWWW....",
            "..GWWWWPPWWWWWWW....",
            "...WWWWWWWWWWWWWW...",
            "...WWWWWWWWWWWWWW...",
            "..WWWWWWWWWWWWWWW...",
            ".WWWWWWWWWWWWWWWW...",
            ".WWWWWWWWWWWWWWWW...",
            "..WWWWWWWWWWWWWW....",
            "...WWWWWWWWWWWW.....",
            "....WWWWWWWWWW......"
        ]
        let blink = tick % 38 == 0 || tick % 38 == 1
        let palette: [Character: NSColor] = [
            "G": outline, "g": grey, "O": outline, "o": ginger,
            "W": cream, "K": blink ? cream : outline,
            "P": NSColor(calibratedRed: 0.92, green: 0.43, blue: 0.48, alpha: 1)
        ]
        let bounce: CGFloat = machine.state == .happy && tick % 4 < 2 ? 4 : 0
        shape(125, 87 + bounce, cat, 3, palette)
        // Tiny whiskers and typing paws.
        rect(129, 115 + bounce, 10, 2, grey)
        rect(180, 115 + bounce, 10, 2, grey)
        let pawShift: CGFloat = tick % 4 < 2 ? 0 : 2
        rect(145, 85 + pawShift, 16, 8, outline)
        rect(147, 88 + pawShift, 12, 5, cream)
        rect(170, 85 - pawShift, 15, 8, outline)
        rect(172, 88 - pawShift, 11, 5, cream)

        // Grey monitor, stand and keyboard in the foreground.
        rect(36, 90, 85, 62, outline)
        rect(40, 94, 77, 54, grey)
        rect(44, 141, 67, 4, NSColor.white.withAlphaComponent(0.18))
        rect(74, 73, 16, 23, outline)
        rect(77, 75, 10, 19, NSColor(calibratedWhite: 0.59, alpha: 1))
        rect(60, 71, 44, 6, outline)
        poly([NSPoint(x: 94,y: 81), NSPoint(x: 163,y: 81),
              NSPoint(x: 183,y: 70), NSPoint(x: 112,y: 70)], outline)
        poly([NSPoint(x: 99,y: 79), NSPoint(x: 161,y: 79),
              NSPoint(x: 176,y: 73), NSPoint(x: 114,y: 73)], NSColor(calibratedWhite: 0.58, alpha: 1))
        for row in 0..<2 {
            for col in 0..<10 {
                rect(111 + CGFloat(col)*5 + CGFloat(row)*3, 75 + CGFloat(row)*3, 3, 1.5,
                     NSColor(calibratedWhite: 0.36, alpha: 1))
            }
        }

        // Neat paper stack at the right end of the desk.
        for i in 0..<9 {
            let y = CGFloat(75 + i * 5)
            rect(201, y, 40, 5, outline)
            rect(204, y + 1, 35, 4, NSColor(calibratedWhite: 0.92, alpha: 1))
        }
        rect(207, 120, 31, 3, NSColor(calibratedWhite: 0.98, alpha: 1))

        // Small metal wastebasket on the floor beneath the right side.
        rect(216, 16, 29, 36, outline)
        rect(220, 19, 21, 31, NSColor(calibratedWhite: 0.63, alpha: 1))
        rect(213, 49, 35, 6, outline)
        rect(217, 51, 27, 3, NSColor(calibratedWhite: 0.85, alpha: 1))
        for x in stride(from: 224, through: 237, by: 6) {
            rect(CGFloat(x), 22, 2, 23, NSColor.white.withAlphaComponent(0.24))
        }
        if machine.state == .alert {
            rect(211, 56, 38, 3, NSColor.systemYellow)
        }
        if machine.state == .throwing || machine.state == .carry {
            rect(205, 85, 13, 14, outline)
            rect(207, 87, 9, 10, cream)
        }
    }

    // Track pointer in global screen coordinates: no cumulative drift and no popup on drag.
    override func mouseDown(with event: NSEvent) {
        dragStartScreen = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartScreen, let origin = windowStart, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x
        let dy = now.y - start.y
        if hypot(dx, dy) >= 3 { dragged = true }
        if dragged { window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !dragged && catHit.contains(point) { showActions(at: point) }
        dragStartScreen = nil
        windowStart = nil
        dragged = false
    }

    private func showActions(at point: NSPoint) {
        let menu = NSMenu()
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
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func showClipboard() {
        let alert = NSAlert()
        alert.messageText = "Clipboard text"
        alert.informativeText = String((NSPasteboard.general.string(forType: .string) ?? "Empty").prefix(500))
        alert.runModal()
    }

    private func urls(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    private func onBin(_ sender: NSDraggingInfo) -> Bool {
        binHit.insetBy(dx: -7, dy: -7).contains(convert(sender.draggingLocation, from: nil))
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                        self?.machine.transition(to: .happy, resetAfter: 1.3)
                    }
                } else {
                    self.machine.transition(to: .error, resetAfter: 2)
                    let alert = NSAlert()
                    alert.messageText = "Some items could not be moved"
                    alert.informativeText = failures.joined(separator: "\n")
                    alert.runModal()
                }
            }
        }
        return true
    }
}
