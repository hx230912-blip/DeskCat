import AppKit

/// Initial interaction prototype. Replace emoji with original pixel-art sprites.
final class CatDropView: NSView {
    private let cat = NSTextField(labelWithString: "🐈")
    private let trash = NSTextField(labelWithString: "🗑️")
    private let message = NSTextField(labelWithString: "Drop files on the bin")
    private let trashService = TrashService()

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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func layout() {
        super.layout()
        cat.frame = NSRect(x: 12, y: 30, width: 90, height: 85)
        trash.frame = NSRect(x: 155, y: 40, width: 65, height: 65)
        message.frame = NSRect(x: 12, y: 8, width: 205, height: 20)
    }

    private func droppedURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !droppedURLs(sender).isEmpty else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        return trash.frame.insetBy(dx: -12, dy: -12).contains(point) ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard draggingEntered(sender) == .move else { return false }
        let urls = droppedURLs(sender)
        guard !urls.isEmpty else { return false }
        let alert = NSAlert()
        alert.messageText = "Move to Trash?"
        alert.informativeText = "Move \(urls.count) item(s) to the macOS Trash? They can be restored from Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        let results = urls.map { trashService.moveToTrash($0) }
        let failures = results.compactMap { result -> String? in
            if case .failure(let error) = result { return error.localizedDescription }
            return nil
        }
        message.stringValue = failures.isEmpty ? "Done! ✨" : "Failed: \(failures.count) item(s)"
        if !failures.isEmpty {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Some files could not be moved"
            errorAlert.informativeText = failures.joined(separator: "\n")
            errorAlert.runModal()
        }
        return failures.isEmpty
    }
}
