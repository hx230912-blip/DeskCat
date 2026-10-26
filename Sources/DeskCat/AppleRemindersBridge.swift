import AppKit
import EventKit
import UserNotifications

/// Read-only bridge to Apple Reminders. Does not copy reminders into local tasks.
@MainActor
final class AppleRemindersBridge {
    static let shared = AppleRemindersBridge()
    private let store = EKEventStore()
    private(set) var today: [EKReminder] = []
    private(set) var errorMessage: String?
    private var timer: Timer?
    private var lastRequest = Date.distantPast

    private init() {}

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
    }

    func refresh() {
        guard Date().timeIntervalSince(lastRequest) > 10 else { return }
        lastRequest = Date()
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .denied || status == .restricted {
            errorMessage = "Allow Reminders access in System Settings → Privacy & Security."
            return
        }
        if status == .notDetermined {
            if #available(macOS 14.0, *) {
                store.requestFullAccessToReminders { [weak self] granted, error in
                    Task { @MainActor in self?.handlePermission(granted, error: error) }
                }
            } else {
                store.requestAccess(to: .reminder) { [weak self] granted, error in
                    Task { @MainActor in self?.handlePermission(granted, error: error) }
                }
            }
            return
        }
        fetchToday()
    }

    private func handlePermission(_ granted: Bool, error: Error?) {
        guard granted else {
            errorMessage = error?.localizedDescription ?? "Reminders permission was not granted."
            return
        }
        fetchToday()
    }

    private func fetchToday() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: start,
            ending: end, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            Task { @MainActor in
                guard let self else { return }
                self.today = (reminders ?? []).sorted {
                    ($0.dueDateComponents?.date ?? .distantFuture) <
                    ($1.dueDateComponents?.date ?? .distantFuture)
                }
                self.errorMessage = nil
                self.scheduleNotifications()
            }
        }
    }

    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.getPendingNotificationRequests { requests in
                let oldIDs = requests.map(\.identifier).filter { $0.hasPrefix("deskcat.apple-reminder.") }
                center.removePendingNotificationRequests(withIdentifiers: oldIDs)
                for reminder in self.today {
                    guard let due = reminder.dueDateComponents?.date,
                          due > Date(), due.timeIntervalSinceNow < 24 * 3600 else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = "DeskCat · Reminder"
                    content.body = reminder.title
                    content.sound = .default
                    let id = "deskcat.apple-reminder." + reminder.calendarItemIdentifier
                    let trigger = UNTimeIntervalNotificationTrigger(
                        timeInterval: max(1, due.timeIntervalSinceNow), repeats: false)
                    center.add(UNNotificationRequest(identifier: id,
                        content: content, trigger: trigger))
                }
            }
        }
    }

    func populateMenu(_ menu: NSMenu) {
        menu.addItem(.separator())
        let header = NSMenuItem(title: "Today's Reminders (\(today.count))",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if let errorMessage {
            let item = NSMenuItem(title: errorMessage, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if today.isEmpty {
            let item = NSMenuItem(title: "No due reminders today", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for reminder in today.prefix(12) {
                let time = reminder.dueDateComponents?.date.map {
                    DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short)
                } ?? "Any time"
                let item = NSMenuItem(title: "\(time) · \(reminder.title)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
    }
}
