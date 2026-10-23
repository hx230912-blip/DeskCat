import Foundation
import EventKit
import UserNotifications

struct DeskTask: Codable, Identifiable {
    var id = UUID()
    var title: String
    var completed = false
    var dueAt: Date?
}

@MainActor
final class DeskTaskStore {
    static let shared = DeskTaskStore()
    private(set) var tasks: [DeskTask] = []
    private let key = "deskcat.tasks.v1"
    private init() { load() }
    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([DeskTask].self, from: data) { tasks = decoded }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(tasks) { UserDefaults.standard.set(data, forKey: key) }
    }
    func add(_ title: String, dueAt: Date?) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let task = DeskTask(title: title, dueAt: dueAt)
        tasks.append(task); save()
        if let dueAt, dueAt > Date() { ReminderService.shared.schedule(task) }
    }
    func toggle(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].completed.toggle()
        ReminderService.shared.cancel(id)
        save()
    }
    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        ReminderService.shared.cancel(id)
        save()
    }
}

@MainActor
final class ReminderService {
    static let shared = ReminderService()
    private init() {}
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    func schedule(_ task: DeskTask) {
        guard let due = task.dueAt, due > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "DeskCat · Task reminder"
        content.body = task.title
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, due.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger))
    }
    func cancel(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
}

@MainActor
final class MeetingService {
    static let shared = MeetingService()
    private let store = EKEventStore()
    private init() {}
    func upcoming(_ completion: @escaping ([EKEvent]?, String?) -> Void) {
        store.requestAccess(to: .event) { [weak self] allowed, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard allowed else {
                    completion(nil, error?.localizedDescription ?? "Calendar permission denied. Check System Settings.")
                    return
                }
                let start = Date()
                let end = Calendar.current.date(byAdding: .day, value: 2, to: start)!
                let predicate = self.store.predicateForEvents(withStart: start, end: end, calendars: nil)
                let events = Array(self.store.events(matching: predicate).prefix(12))
                self.scheduleMeetingReminders(events)
                completion(events, nil)
            }
        }
    }
    private func scheduleMeetingReminders(_ events: [EKEvent]) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        for event in events {
            let fire = event.startDate.addingTimeInterval(-300)
            guard fire > Date(), let identifier = event.eventIdentifier else { continue }
            let content = UNMutableNotificationContent()
            content.title = "DeskCat · Meeting in 5 minutes"
            content.body = event.title ?? "Upcoming calendar event"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fire.timeIntervalSinceNow), repeats: false)
            let key = "deskcat.meeting." + identifier + "." + String(Int(event.startDate.timeIntervalSince1970))
            center.add(UNNotificationRequest(identifier: key, content: content, trigger: trigger))
        }
    }
}
