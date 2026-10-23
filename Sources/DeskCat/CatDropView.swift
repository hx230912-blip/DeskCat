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
        machine.onChange = { [weak self] _ in self?.needsDisplay = true }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.ticks += 1
                if self.ticks % 150 == 0 { self.machine.idleActivity() }
                self.needsDisplay = true
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
        guard let image else { return }
        drawImage(image, in: bounds)

        // Lightweight visual animation layers over the preserved reference artwork.
        let phase = CGFloat(ticks % 30) / 30
        switch machine.state {
        case .sleeping:
            drawGlyph("z", at: NSPoint(x: 150, y: 147 + phase * 8), color: .systemIndigo, size: 12)
            if ticks % 45 < 20 { drawGlyph("z", at: NSPoint(x: 163, y: 157), color: .systemIndigo, size: 9) }
        case .grooming:
            let dx: CGFloat = ticks % 10 < 5 ? 0 : 3
            drawGlyph("♥", at: NSPoint(x: 137 + dx, y: 135), color: .systemPink, size: 9)
        case .walking, .carry:
            let dx: CGFloat = CGFloat(ticks % 12) * 2
            drawGlyph("▣", at: NSPoint(x: 165 + dx, y: 79), color: .white, size: 15)
        case .happy:
            drawGlyph("✦", at: NSPoint(x: 161, y: 143 + (ticks % 6 < 3 ? 2 : 0)), color: .systemYellow, size: 15)
        case .alert:
            drawGlyph("!", at: NSPoint(x: 218, y: 48), color: .systemYellow, size: 13)
        case .error:
            drawGlyph("!", at: NSPoint(x: 149, y: 149), color: .systemRed, size: 13)
        default: break
        }
        if let start = trashAnimationStart {
            let t = min(1, Date().timeIntervalSince(start) / 1.0)
            // Arc from cat to the floor bin. A paper icon travels over the static art.
            let x = 148 + 67 * t
            let y = 100 - 62 * t + 32 * sin(.pi * t)
            drawGlyph("▤", at: NSPoint(x: x, y: y), color: .white, size: 18)
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
        if didDrag { window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !didDrag { showMenu(for: point) }
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
        let alert = NSAlert()
        alert.messageText = "Move \(urls.count) item(s) to macOS Trash?"
        alert.informativeText = "Files can normally be restored from Trash. This action is not permanent deletion."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            machine.transition(to: .idle)
            return false
        }
        processing = true
        machine.transition(to: .carry)
        // Complete the visual arc first; then move to Trash and report actual outcome.
        trashAnimationStart = Date()
        trashCompletion = { [weak self] in
            guard let self else { return }
            self.machine.transition(to: .throwing)
            let failures = urls.compactMap { url -> String? in
                switch self.trashService.moveToTrash(url) {
                case .success: return nil
                case .failure(let error): return error.localizedDescription
                }
            }
            self.processing = false
            if failures.isEmpty {
                self.machine.transition(to: .happy, resetAfter: 2)
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
