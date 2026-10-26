import AppKit

/// Chef Edition: fully transparent scene, pixel-drawn cat, stove and Trash.
/// All artwork is drawn at runtime, so no bundled PNG is required.
@MainActor
final class ChefCatView: NSView {
    private let bridge = AppleRemindersBridge.shared
    private let trashService = TrashService()
    private var clock: Timer?
    private var spriteCache: [String: NSImage] = [:]
    private var started = Date()
    private var lastCount = 0
    private var celebrationUntil = Date.distantPast
    private var deletionUntil = Date.distantPast
    private var deletionStarted = Date.distantPast
    private var busy = false
    private var feedback = ""
    private var feedbackUntil = Date.distantPast
    private var movingStart: NSPoint?
    private var windowStart: NSPoint?
    private let bin = NSRect(x: 218, y: 12, width: 47, height: 62)

    override var isFlipped: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        clock = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    deinit { clock?.invalidate() }

    private var pending: Int {
        bridge.today.count + DeskTaskStore.shared.tasks.filter { !$0.completed }.count
    }
    private func tick() {
        let count = pending
        if lastCount > count && count >= 0 { celebrationUntil = Date().addingTimeInterval(2.5) }
        lastCount = count
        needsDisplay = true
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
        color.setFill()
        NSRect(x: x, y: y, width: w, height: h).fill()
    }
    private func px(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: NSColor, scale: CGFloat = 4) {
        rect(CGFloat(x) * scale, CGFloat(y) * scale, CGFloat(w) * scale, CGFloat(h) * scale, color)
    }
    private let outline = NSColor(calibratedRed: 0.18, green: 0.13, blue: 0.17, alpha: 1)
    private let fur = NSColor(calibratedRed: 0.86, green: 0.43, blue: 0.19, alpha: 1)
    private let lightFur = NSColor(calibratedRed: 1, green: 0.76, blue: 0.48, alpha: 1)
    private let cream = NSColor(calibratedRed: 1, green: 0.93, blue: 0.79, alpha: 1)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let now = Date()
        let t = now.timeIntervalSince(started)
        let cooking = pending > 0
        let celebrating = now < celebrationUntil
        let deleting = now < deletionUntil
        let sleep = !cooking && !celebrating && !deleting && Int(t / 13) % 4 == 2
        let bob = (cooking || celebrating) ? CGFloat(Int(t * 3) % 2) * 2 : 0
        // Only the props and character are drawn; the rest remains transparent.
        drawBin()
        if cooking { drawStove(time: t) }
        let state = deleting ? "carry" : (celebrating ? "celebrate" : (cooking ? "cook" : (sleep ? "sleep" : (Int(t / 8) % 3 == 1 ? "walk" : "idle"))))
        let walkOffset: CGFloat = state == "walk" ? CGFloat(Int(t * 9) % 22) - 11 : 0
        drawSprite(state: state, frame: Int(t * (state == "cook" ? 3 : 5)) % 2,
                   x: (deleting ? 112 : (cooking ? 75 : 79)) + walkOffset,
                   y: (cooking ? 42 : 20) + bob)
        if deleting { drawPaper(x: 158 + CGFloat(min(1, now.timeIntervalSince(deletionStarted))) * 62,
                                y: 79 - CGFloat(min(1, now.timeIntervalSince(deletionStarted))) * 27) }
        if sleep { label("z z Z", x: 142, y: 134, size: 15, color: .systemBlue) }
        if celebrating { label("♥ ✨", x: 145, y: 150, size: 18, color: .systemOrange) }
        if now < feedbackUntil { label(feedback, x: 18, y: 170, size: 11, color: .labelColor) }
    }

    private func drawSprite(state: String, frame: Int, x: CGFloat, y: CGFloat) {
        let index = ["walk", "cook", "celebrate"].contains(state) ? frame : 0
        let key = "cat_" + state + "_" + String(format: "%02d", index)
        if spriteCache[key] == nil {
            let url = Bundle.module.url(forResource: key, withExtension: "png", subdirectory: "Sprites")
                ?? Bundle.module.url(forResource: key, withExtension: "png")
            if let url, let image = NSImage(contentsOf: url) { spriteCache[key] = image }
        }
        guard let image = spriteCache[key] else {
            // Missing sprites should not block Reminders or Trash features.
            label("🐈‍⬛", x: x, y: y + 35, size: 60, color: .labelColor)
            return
        }
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: NSRect(x: x, y: y, width: 122, height: 122),
                   from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func drawStove(time: Double) {
        let wood = NSColor(calibratedRed: 0.48, green: 0.29, blue: 0.18, alpha: 1)
        rect(22, 14, 176, 33, outline)
        rect(27, 19, 166, 23, wood)
        rect(30, 44, 162, 9, NSColor(calibratedRed: 0.69, green: 0.47, blue: 0.31, alpha: 1))
        rect(48, 51, 110, 12, outline)
        rect(58, 63, 90, 6, .darkGray)
        rect(69, 69, 70, 8, outline)
        rect(77, 77, 55, 4, .gray)
        for i in 0..<5 {
            let flicker = CGFloat(Int(time * 7 + Double(i)) % 3) * 3
            rect(81 + CGFloat(i) * 10, 53, 6, 12 + flicker, .systemOrange)
            rect(83 + CGFloat(i) * 10, 55, 3, 6 + flicker, .systemYellow)
        }
        rect(157, 45, 21, 26, .white)
        for i in 0..<3 { rect(161 + CGFloat(i) * 6, 47, 3, 20, .systemRed) }
    }
    private func drawBin() {
        rect(218, 12, 47, 55, outline)
        rect(223, 17, 37, 44, NSColor(calibratedWhite: 0.31, alpha: 1))
        rect(213, 64, 57, 9, outline)
        rect(221, 73, 40, 5, .gray)
        rect(234, 38, 15, 3, .white)
        rect(240, 32, 3, 15, .white)
    }
    private func drawPaper(x: CGFloat, y: CGFloat) {
        rect(x, y, 18, 22, outline)
        rect(x + 3, y + 3, 12, 16, .white)
        rect(x + 5, y + 12, 8, 2, .gray)
    }
    private func label(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor) {
        (string as NSString).draw(at: NSPoint(x: x, y: y),
            withAttributes: [.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: color])
    }
    private func show(_ message: String) {
        feedback = message; feedbackUntil = Date().addingTimeInterval(3)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        movingStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
    }
    override func mouseDragged(with event: NSEvent) {
        guard let movingStart, let windowStart else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - movingStart.x, dy = current.y - movingStart.y
        if hypot(dx, dy) > 4 { window?.setFrameOrigin(NSPoint(x: windowStart.x + dx, y: windowStart.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        defer { movingStart = nil; windowStart = nil }
        guard let movingStart else { return }
        if hypot(NSEvent.mouseLocation.x - movingStart.x,
                 NSEvent.mouseLocation.y - movingStart.y) > 4 { return }
        let menu = NSMenu()
        let task = NSMenuItem(title: "Today's Reminders (\(bridge.today.count))", action: nil, keyEquivalent: "")
        task.isEnabled = false; menu.addItem(task)
        for reminder in bridge.today.prefix(8) {
            let row = NSMenuItem(title: reminder.title, action: nil, keyEquivalent: "")
            row.isEnabled = false; menu.addItem(row)
        }
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }
    private func urls(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    private func validDrop(_ info: NSDraggingInfo) -> Bool {
        !busy && !urls(info).isEmpty &&
        bin.insetBy(dx: -10, dy: -10).contains(convert(info.draggingLocation, from: nil))
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        validDrop(sender) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard validDrop(sender) else { return false }
        let files = urls(sender)
        let alert = NSAlert()
        alert.messageText = "Move \(files.count) item(s) to Trash?"
        alert.informativeText = "DeskCat will use the macOS Trash. Items are not permanently deleted."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        busy = true
        // Actual file I/O completes first; animation never gates the operation.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let service = TrashService()
            let failures = files.compactMap { file -> String? in
                if case .failure(let error) = service.moveToTrash(file) { return error.localizedDescription }
                return nil
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                if failures.isEmpty {
                    self.deletionStarted = Date()
                    self.deletionUntil = Date().addingTimeInterval(1.4)
                    self.show("Moved to Trash ✓")
                } else {
                    self.show("\(failures.count) file(s) failed")
                    let error = NSAlert()
                    error.messageText = "Some files could not be moved"
                    error.informativeText = failures.joined(separator: "\n")
                    error.runModal()
                }
            }
        }
        return true
    }
}
