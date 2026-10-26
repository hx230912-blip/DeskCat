import AppKit

/// Chef Edition: fully transparent scene, pixel-drawn cat, stove and Trash.
/// All artwork is drawn at runtime, so no bundled PNG is required.
@MainActor
final class ChefCatView: NSView {
    private let bridge = AppleRemindersBridge.shared
    private let trashService = TrashService()
    private var clock: Timer?
    private var spriteCache: [String: NSImage] = [:]
    private var missingSprites = Set<String>()
    private var previousAnimationState = ""
    private var animationStarted = Date()
    private var transitionStarted = Date.distantPast
    private var previousSpriteState = "idle"
    private var previousSpriteFrame = 0
    private let animationFrameCounts: [String: Int] = [
        "idle": 4, "walk": 8, "sleep": 6, "cook": 8,
        "carry": 8, "celebrate": 8
    ]
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
    private let artScale: CGFloat = 0.85
    private let bin = NSRect(x: 225, y: 18, width: 48, height: 65)

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
        // Uniformly scale the entire transparent scene, including the cat,
        // stove, bin, effects and labels. Keep all original art coordinates.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let scale = AffineTransform(scale: artScale)
        NSAffineTransform(transform: scale).concat()
        let now = Date()
        let t = now.timeIntervalSince(started)
        let cooking = pending > 0
        let celebrating = now < celebrationUntil
        let deleting = now < deletionUntil
        let sleep = !cooking && !celebrating && !deleting && Int(t / 13) % 4 == 2
        let state = deleting ? "carry" :
            (celebrating ? "celebrate" :
            (cooking ? "cook" :
            (sleep ? "sleep" : (Int(t / 8) % 3 == 1 ? "walk" : "idle"))))
        if state != previousAnimationState {
            previousSpriteState = previousAnimationState.isEmpty ? state : previousAnimationState
            previousSpriteFrame = currentFrame(for: previousSpriteState, elapsed: now.timeIntervalSince(animationStarted))
            transitionStarted = now
            previousAnimationState = state
            animationStarted = now
        }
        let elapsed = now.timeIntervalSince(animationStarted)
        let frameCount = animationFrameCounts[state] ?? 1
        let frame = currentFrame(for: state, elapsed: elapsed) % frameCount
        let walkOffset: CGFloat = state == "walk" ? CGFloat(sin(elapsed * 1.7)) * 16 : 0
        let bob: CGFloat = (state == "cook" || state == "celebrate") ? CGFloat(sin(elapsed * 8)) * 1.2 : 0
        // The cat is behind the counter when cooking, in front when roaming.
        if cooking && !deleting && !celebrating {
            drawAnimatedSprite(state: state, frame: frame, now: now,
                       x: 70 + walkOffset, y: 48 + bob)
            // Cooking sprites include the stove and pan; avoid drawing a second stove.
        } else {
            drawStove(time: t, active: false)
            drawAnimatedSprite(state: state, frame: frame, now: now,
                       x: (deleting ? 125 : 80) + walkOffset, y: 18 + bob)
        }
        drawBin(open: deleting)
        if deleting {
            let progress = CGFloat(min(1, now.timeIntervalSince(deletionStarted) / 1.4))
            if progress < 0.9 {
                drawPaper(x: 166 + progress * 66, y: 86 - progress * 33)
            }
        }
        if sleep { label("z z Z", x: 142, y: 134, size: 15, color: .systemBlue) }
        if celebrating { label("♥ ✨", x: 145, y: 150, size: 18, color: .systemOrange) }
        if now < feedbackUntil { label(feedback, x: 18, y: 170, size: 11, color: .labelColor) }
    }

    private func currentFrame(for state: String, elapsed: TimeInterval) -> Int {
        let durations: [Double] = switch state {
        case "sleep": [0.28, 0.32, 0.36, 0.36, 0.32, 0.28]
        case "walk": [0.10, 0.12, 0.10, 0.12, 0.10, 0.12, 0.10, 0.12]
        case "cook": [0.15, 0.12, 0.11, 0.14, 0.15, 0.12, 0.11, 0.14]
        case "carry": [0.12, 0.12, 0.16, 0.12, 0.12, 0.16, 0.12, 0.12]
        case "celebrate": [0.12, 0.10, 0.10, 0.16, 0.12, 0.10, 0.10, 0.16]
        default: [0.35, 0.30, 0.35, 0.30]
        }
        let cycle = durations.reduce(0, +)
        var time = max(0, elapsed).truncatingRemainder(dividingBy: cycle)
        for (index, duration) in durations.enumerated() {
            if time < duration { return index }
            time -= duration
        }
        return durations.count - 1
    }

    private func drawAnimatedSprite(state: String, frame: Int, now: Date, x: CGFloat, y: CGFloat) {
        let transitionDuration = 0.16
        let blend = min(1, max(0, now.timeIntervalSince(transitionStarted) / transitionDuration))
        if blend < 1 && previousSpriteState != state {
            drawSprite(state: previousSpriteState, frame: previousSpriteFrame,
                       x: x, y: y, opacity: CGFloat(1 - blend))
        }
        drawSprite(state: state, frame: frame, x: x, y: y, opacity: CGFloat(blend))
    }

    private func drawSprite(state: String, frame: Int, x: CGFloat, y: CGFloat, opacity: CGFloat = 1) {
        // Look up a complete animation sequence, falling back to the older
        // two-frame sprites until the matching art is installed.
        let candidates = [
            "cat_" + state + "_" + String(format: "%02d", frame),
            "cat_" + state + "_" + String(format: "%02d", frame % 2),
            "cat_" + state + "_00",
            "cat_idle_00"
        ]
        var selected: NSImage?
        for key in candidates {
            if let cached = spriteCache[key] { selected = cached; break }
            if missingSprites.contains(key) { continue }
            let url = Bundle.module.url(forResource: key, withExtension: "png", subdirectory: "Sprites")
                ?? Bundle.module.url(forResource: key, withExtension: "png")
            if let url, let image = NSImage(contentsOf: url) {
                spriteCache[key] = image
                selected = image
                break
            }
            missingSprites.insert(key)
        }
        guard let image = selected else { return }
        NSGraphicsContext.current?.imageInterpolation = .none
        let target = NSRect(x: x, y: y, width: 118, height: 118)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: opacity)
    }

    private func drawStove(time: Double, active: Bool) {
        // Compact countertop and gas burner; transparent everywhere else.
        let edge = NSColor(calibratedRed: 0.20, green: 0.14, blue: 0.18, alpha: 1)
        let wood = NSColor(calibratedRed: 0.57, green: 0.32, blue: 0.18, alpha: 1)
        let highlight = NSColor(calibratedRed: 0.85, green: 0.57, blue: 0.34, alpha: 1)
        rect(15, 20, 185, 32, edge)
        rect(20, 25, 175, 23, wood)
        rect(20, 44, 175, 6, highlight)
        rect(23, 29, 54, 3, highlight.withAlphaComponent(0.55))
        // Stove fascia and control knobs.
        rect(55, 49, 96, 29, edge)
        rect(60, 53, 86, 20, NSColor(calibratedWhite: 0.28, alpha: 1))
        for x in stride(from: CGFloat(74), through: CGFloat(128), by: 26) {
            rect(x, 56, 11, 11, edge)
            rect(x + 3, 60, 5, 5, .gray)
        }
        // Frying pan and handle.
        rect(57, 91, 93, 8, edge)
        rect(65, 84, 79, 13, NSColor(calibratedWhite: 0.13, alpha: 1))
        rect(145, 91, 23, 5, edge)
        rect(67, 96, 72, 3, NSColor(calibratedWhite: 0.48, alpha: 1))
        // Food bits jump a little, rather than covering the desktop with effects.
        if active {
        for i in 0..<6 {
            let x = CGFloat(75 + i * 10)
            let jump = CGFloat(Int(time * 4 + Double(i)) % 3) * 3
            rect(x, 99 + jump, 5, 4, i.isMultiple(of: 2) ? .systemGreen : .systemOrange)
        }
        for i in 0..<6 {
            let x = CGFloat(74 + i * 10)
            let flicker = CGFloat(Int(time * 8 + Double(i)) % 3) * 3
            rect(x, 78, 7, 8 + flicker, .systemOrange)
            rect(x + 2, 80, 3, 5 + flicker, .systemYellow)
        }
        }
        // Small towel and spice bottle give the stove a friendly silhouette.
        rect(174, 51, 20, 29, .white)
        for i in 0..<3 { rect(178 + CGFloat(i * 5), 53, 2, 25, .systemRed) }
        rect(23, 53, 15, 27, edge)
        rect(25, 57, 11, 19, NSColor(calibratedRed: 0.31, green: 0.52, blue: 0.29, alpha: 1))
        rect(27, 78, 7, 4, .systemYellow)
    }

    private func drawBin(open: Bool) {
        let edge = NSColor(calibratedRed: 0.19, green: 0.15, blue: 0.22, alpha: 1)
        let metal = NSColor(calibratedRed: 0.38, green: 0.38, blue: 0.46, alpha: 1)
        rect(227, 18, 44, 51, edge)
        rect(232, 23, 34, 42, metal)
        rect(237, 26, 4, 34, .gray)
        rect(257, 26, 4, 34, .gray)
        if open {
            rect(217, 80, 54, 8, edge)
            rect(220, 85, 47, 3, metal)
        } else {
            rect(222, 69, 54, 9, edge)
            rect(228, 77, 40, 5, metal)
        }
        // Recycle mark (the bin is a drop target, actual action is Move to Trash).
        label("↻", x: 239, y: 38, size: 19, color: .white)
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
        bin.insetBy(dx: -10, dy: -10).contains(NSPoint(
            x: convert(info.draggingLocation, from: nil).x / artScale,
            y: convert(info.draggingLocation, from: nil).y / artScale))
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
