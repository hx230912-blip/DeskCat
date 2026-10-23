import AppKit

/// Transparent, movable pixel-art companion. Coordinates are in a 256×176 view.
@MainActor
final class CatDropView: NSView {
    private let machine = CatStateMachine()
    private let trashService = TrashService()
    private let tasks = DeskTaskStore.shared
    private var timer: Timer?
    private var ticks = 0
    private var dragStart: NSPoint?
    private var origin: NSPoint?
    private var didDrag = false
    private var processing = false
    private var trashAnimationStart: Date?
    private var trashCompletion: (() -> Void)?
    private var toast: String?
    private var toastUntil: Date = .distantPast
    private var animationName = "idle"
    private var animationStarted = Date()
    private var nextMeeting: Date?
    private var lastMeetingCheck = Date.distantPast
    private var busyUntil = Date.distantPast
    private var dragAnimating = false
    private var lastBehavior = Date.distantPast
    private var trashJourneyStarted: Date?
    private var trashPhase = 0
    private var trashPhaseStart = Date.distantPast
    private var trashTargets: [URL] = []
    private var returnStarted = Date.distantPast
    private var imageCache: [String: NSImage] = [:]
    private let frames: [String: Int] = ["idle":2,"groom":8,"sleep":6,"walk":8,"stand":6,"carry":6,"throw":8,"happy":6,"typing":8,"clock":6,"walkback":8]
    private func setAnimation(_ name: String) {
        animationName = name
        animationStarted = Date()
        needsDisplay = true
    }
    private func resource(_ name: String) -> NSImage? {
        if let cached = imageCache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        imageCache[name] = img
        return img
    }

    // Render in a fixed logical canvas; preserve transparency.
    private let catRect = NSRect(x: 98, y: 62, width: 78, height: 83)
    private let monitorRect = NSRect(x: 12, y: 60, width: 85, height: 78)
    private let paperRect = NSRect(x: 178, y: 60, width: 57, height: 72)
    private let binRect = NSRect(x: 193, y: 2, width: 51, height: 49)
    private let deskRect = NSRect(x: 9, y: 35, width: 229, height: 31)

    private lazy var image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "DeskCatScene", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        machine.onChange = { [weak self] state in
            guard let self else { return }
            if !self.processing {
                let name: String
                switch state {
                case .grooming: name = "groom"
                case .sleeping: name = "sleep"
                case .walking: name = "walk"
                case .happy: name = "happy"
                default: name = "idle"
                }
                self.setAnimation(name)
            }
            self.needsDisplay = true
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.ticks += 1
                if self.ticks % 150 == 0 { self.updateBehavior() }
                self.needsDisplay = true
            }
        }
    }
    private func updateBehavior() {
        guard !processing, !dragAnimating else { return }
        let now = Date()
        if now.timeIntervalSince(lastMeetingCheck) > 120 {
            lastMeetingCheck = now
            MeetingService.shared.upcoming { [weak self] events, _ in
                guard let self else { return }
                self.nextMeeting = events?.filter { $0.startDate > Date() }.map { $0.startDate }.min()
                self.updateBehavior()
            }
        }
        if now < busyUntil { return }
        if let nextMeeting, nextMeeting.timeIntervalSince(now) > 0,
           nextMeeting.timeIntervalSince(now) <= 7200 {
            if animationName != "clock" { setAnimation("clock") }
        } else if tasks.tasks.filter({ !$0.completed }).count >= 3 {
            if animationName != "typing" { setAnimation("typing") }
        } else if now.timeIntervalSince(lastBehavior) >= 14 {
            lastBehavior = now
            if tasks.tasks.contains(where: { !$0.completed }) {
                setAnimation("typing")
            } else {
                setAnimation(Bool.random() ? "groom" : "sleep")
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
    deinit { timer?.invalidate() }

    private func drawImage(_ image: NSImage, in rect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let background = resource("DeskCatBackground") {
            drawImage(background, in: bounds)
            let count = frames[animationName] ?? 2
            let elapsed = max(0, Date().timeIntervalSince(animationStarted))
            let fps: Double = animationName == "sleep" ? 3 : (animationName == "groom" ? 7 : 10)
            let frame = Int(elapsed * fps) % count
            let spriteName = animationName == "walkback" ? "walk" : animationName
            let spriteFrame = animationName == "walkback" ? max(0, count - 1 - frame) : frame
            let key = String(format: "Cat_%@_%02d", spriteName, spriteFrame)
            if let sprite = resource(key) ?? resource("Cat_idle_00") {
                var dx: CGFloat = 0
                var dy: CGFloat = 0
                if processing {
                    let t = min(1, max(0, Date().timeIntervalSince(trashPhaseStart) / 0.75))
                    let eased = t * t * (3 - 2 * t)
                    if trashPhase == 1 { dx = CGFloat(70 * eased); dy = CGFloat(-42 * eased) }
                    if trashPhase >= 2 { dx = 70; dy = -42 }
                } else if animationName == "walkback" {
                    let t = min(1, max(0, Date().timeIntervalSince(returnStarted) / 0.75))
                    let eased = t * t * (3 - 2 * t)
                    dx = CGFloat(70 * (1 - eased))
                    dy = CGFloat(-42 * (1 - eased))
                }
                drawImage(sprite, in: bounds.offsetBy(dx: dx, dy: dy))
            }
        } else if let image { drawImage(image, in: bounds) }

        if let start = trashAnimationStart {
            let t = min(1, Date().timeIntervalSince(start) / 0.85)
            let x = 191 + 26 * t
            let y = 91 - 54 * t + 22 * sin(.pi * t)
            drawGlyph("▤", at: NSPoint(x: x, y: y), color: .white, size: 15)
            if t >= 1 {
                trashAnimationStart = nil
                let completion = trashCompletion
                trashCompletion = nil
                DispatchQueue.main.async { completion?() }
            }
        }
        if let toast, Date() < toastUntil {
            drawGlyph(toast, at: NSPoint(x: 15, y: 156), color: .labelColor, size: 10)
        }
    }
    private func drawGlyph(_ text: String, at point: NSPoint, color: NSColor, size: CGFloat) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: size),
            .foregroundColor: color,
            .strokeColor: NSColor.white.withAlphaComponent(0.65),
            .strokeWidth: -2
        ])
    }
    private func showToast(_ message: String) {
        toast = message
        toastUntil = Date().addingTimeInterval(2)
        needsDisplay = true
    }

    // Drag entire workstation with a 4-point threshold; clicks never move it.
    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        origin = window?.frame.origin
        didDrag = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let origin, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if hypot(dx, dy) > 4 { didDrag = true }
        if didDrag {
            if !dragAnimating && !processing { dragAnimating = true; setAnimation("walk") }
            window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        }
    }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !didDrag { showMenu(for: point) }
        if dragAnimating {
            dragAnimating = false
            busyUntil = Date().addingTimeInterval(0.5)
            setAnimation("idle")
        }
        dragStart = nil
        origin = nil
        didDrag = false
    }
    private func showMenu(for point: NSPoint) {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector) {
            let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
            row.target = self
            menu.addItem(row)
        }
        if binRect.contains(point) {
            item("Drop files here to move to Trash", #selector(trashHelp))
        } else if paperRect.contains(point) {
            item("To-do list…", #selector(showTasks))
            item("Add task…", #selector(addTask))
        } else if monitorRect.contains(point) {
            item("Upcoming meetings…", #selector(showMeetings))
            item("Open Calendar", #selector(openCalendar))
        } else if catRect.contains(point) {
            item("To-do list…", #selector(showTasks))
            item("Add task…", #selector(addTask))
            item("Upcoming meetings…", #selector(showMeetings))
            menu.addItem(.separator())
            item("Play: Groom", #selector(groom))
            item("Play: Sleep", #selector(sleep))
            item("Play: Walk", #selector(walk))
        } else if deskRect.contains(point) {
            item("Drag desk to reposition", #selector(dragHelp))
            item("Open Downloads", #selector(openDownloads))
        } else {
            item("DeskCat", #selector(dragHelp))
        }
        menu.popUp(positioning: nil, at: point, in: self)
    }
    @objc private func trashHelp() { showToast("Drop a file on the bin") }
    @objc private func dragHelp() { showToast("Drag to move DeskCat") }
    @objc private func groom() { machine.transition(to: .grooming, resetAfter: 5) }
    @objc private func sleep() { machine.transition(to: .sleeping, resetAfter: 8) }
    @objc private func walk() { machine.transition(to: .walking, resetAfter: 2) }
    @objc private func openCalendar() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
    @objc private func openDownloads() {
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func addTask() {
        let alert = NSAlert()
        alert.messageText = "New DeskCat task"
        alert.informativeText = "Enter a task. Optionally set a reminder in minutes."
        let title = NSTextField(frame: NSRect(x: 0, y: 32, width: 280, height: 24))
        title.placeholderString = "Task name"
        let minutes = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        minutes.placeholderString = "Reminder in minutes (optional)"
        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 58))
        stack.addSubview(title); stack.addSubview(minutes)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let n = Double(minutes.stringValue)
        let due = n.flatMap { $0 > 0 ? Date().addingTimeInterval($0 * 60) : nil }
        tasks.add(title.stringValue, dueAt: due)
        if due != nil { ReminderService.shared.requestPermission() }
        machine.transition(to: .happy, resetAfter: 1.5)
        showToast("Task saved")
    }
    @objc private func showTasks() {
        let pending = tasks.tasks.filter { !$0.completed }
        let alert = NSAlert()
        alert.messageText = "DeskCat tasks"
        if pending.isEmpty {
            alert.informativeText = "All done! Click Add to create a task."
            alert.addButton(withTitle: "Add")
            alert.addButton(withTitle: "Close")
            if alert.runModal() == .alertFirstButtonReturn { addTask() }
            return
        }
        let labels = pending.prefix(20).enumerated().map { "\($0.offset + 1). \($0.element.title)" }
        alert.informativeText = labels.joined(separator: "\n")
        alert.addButton(withTitle: "Complete first")
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Close")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            tasks.toggle(pending[0].id)
            machine.transition(to: .happy, resetAfter: 1.5)
        case .alertSecondButtonReturn: addTask()
        default: break
        }
    }
    @objc private func showMeetings() {
        MeetingService.shared.upcoming { [weak self] events, error in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = "Upcoming meetings (48 hours)"
            if let error { alert.informativeText = error }
            else if let events, !events.isEmpty {
                let fmt = DateFormatter()
                fmt.dateStyle = .short
                fmt.timeStyle = .short
                alert.informativeText = events.map {
                    "\(fmt.string(from: $0.startDate))  \($0.title ?? "Untitled")"
                }.joined(separator: "\n")
            } else { alert.informativeText = "No upcoming events." }
            alert.addButton(withTitle: "OK")
            alert.runModal()
            self.machine.transition(to: .idle)
        }
    }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    private func overBin(_ sender: NSDraggingInfo) -> Bool {
        binRect.insetBy(dx: -7, dy: -7).contains(convert(sender.draggingLocation, from: nil))
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !processing, !fileURLs(sender).isEmpty, overBin(sender) else { return [] }
        machine.transition(to: .alert)
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        if !processing { machine.transition(to: .idle) }
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !processing, overBin(sender) else { return false }
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        // Dropping a file onto the bin is explicit consent to move it to macOS Trash.
        processing = true
        trashTargets = urls
        trashPhase = 0
        trashPhaseStart = Date()
        setAnimation("stand")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, self.processing else { return }
            self.trashPhase = 1
            self.trashPhaseStart = Date()
            self.setAnimation("walk")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) { [weak self] in
            guard let self, self.processing else { return }
            self.trashPhase = 2
            self.setAnimation("carry")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) { [weak self] in
            guard let self, self.processing else { return }
            self.trashPhase = 3
            self.setAnimation("throw")
            self.trashAnimationStart = Date()
        }
        trashCompletion = { [weak self] in
            guard let self else { return }
            let failures = self.trashTargets.compactMap { url -> String? in
                switch self.trashService.moveToTrash(url) {
                case .success: return nil
                case .failure(let error): return error.localizedDescription
                }
            }
            self.trashTargets = []
            self.processing = false
            self.trashPhase = 0
            self.returnStarted = Date()
            if failures.isEmpty {
                self.setAnimation("walkback")
                self.busyUntil = Date().addingTimeInterval(2)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                    guard let self else { return }
                    self.machine.transition(to: .happy, resetAfter: 1.2)
                }
                self.showToast("Moved to Trash")
            } else {
                self.machine.transition(to: .error, resetAfter: 3)
                let warning = NSAlert()
                warning.messageText = "Some files could not be moved"
                warning.informativeText = failures.joined(separator: "\n")
                warning.runModal()
            }
        }
        return true
    }
}
