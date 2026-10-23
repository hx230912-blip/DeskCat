import AppKit

/// Functional prototype with animated emoji placeholders.
/// Original pixel sprites can replace the label without changing the drag logic.
@MainActor
final class CatDropView: NSView {
    private let cat = NSTextField(labelWithString: "🐈")
    private let trash = NSTextField(labelWithString: "🗑️")
    private let message = NSTextField(labelWithString: "Drop test files on the bin")
    private let trashService = TrashService()
    private let machine = CatStateMachine()
    private var isProcessing = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        for label in [cat, trash, message] {
            label.isBezeled = false
            label.drawsBackground = false
            addSubview(label)
        }
        cat.font = .systemFont(ofSize: 64)
        trash.font = .systemFont(ofSize: 40)
        message.font = .systemFont(ofSize: 10)
        message.textColor = .secondaryLabelColor
        machine.onChange = { [weak self] state in self?.render(state) }
        render(.idle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func layout() {
        super.layout()
        cat.frame = NSRect(x: 12, y: 30, width: 90, height: 85)
        trash.frame = NSRect(x: 155, y: 40, width: 65, height: 65)
        message.frame = NSRect(x: 12, y: 8, width: 210, height: 20)
    }

    private func render(_ state: CatState) {
        cat.stringValue = switch state {
        case .idle: "🐈"
        case .alert: "😺"
        case .carry, .walk: "🐈"
        case .throwing: "🐱"
        case .happy: "😸"
        case .error: "🙀"
        }
        if state == .idle { message.stringValue = "Drop test files on the bin" }
    }

    private func droppedURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    private func overBin(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        return trash.frame.insetBy(dx: -12, dy: -12).contains(point)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isProcessing, !droppedURLs(sender).isEmpty, overBin(sender) else {
            if !isProcessing { machine.transition(to: .idle) }
            return []
        }
        if machine.state != .alert { machine.transition(to: .alert) }
        return .copy // Do not promise Finder a synchronous move.
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if !isProcessing { machine.transition(to: .idle) }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !isProcessing, overBin(sender) else { return false }
        let urls = droppedURLs(sender)
        guard !urls.isEmpty else { return false }
        let alert = NSAlert()
        alert.messageText = "Move to Trash?"
        alert.informativeText = "Move \(urls.count) item(s) to the macOS Trash? Test with disposable files first."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            machine.transition(to: .idle)
            return false
        }
        isProcessing = true
        machine.transition(to: .carry)
        message.stringValue = "Moving to Trash…"
        // A dedicated serial queue keeps file I/O off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcomes = urls.map { self?.trashService.moveToTrash($0) }
            let failures = outcomes.compactMap { outcome -> String? in
                guard let outcome else { return "Operation unavailable" }
                if case .failure(let error) = outcome { return error.localizedDescription }
                return nil
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isProcessing = false
                if failures.isEmpty {
                    self.machine.transition(to: .throwing)
                    self.message.stringValue = "Moved to Trash!"
                    self.machine.transition(to: .happy, resetAfter: 1.4)
                } else {
                    self.machine.transition(to: .error, resetAfter: 3)
                    self.message.stringValue = "\(failures.count) item(s) failed"
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Some files could not be moved"
                    errorAlert.informativeText = failures.joined(separator: "\n")
                    errorAlert.runModal()
                }
            }
        }
        return true
    }
}
