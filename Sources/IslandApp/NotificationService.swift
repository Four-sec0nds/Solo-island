import Foundation
import UserNotifications
import IslandCore

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    let center = UNUserNotificationCenter.current()
    var onAction: ((String, UUID) -> Void)?
    var onError: ((String) -> Void)?
    private let queue = DispatchQueue(label: "app.solo.island.notifications")
    private var revisions: [String: Int] = [:]
    override init() {
        super.init()
        center.delegate = self
        let category = UNNotificationCategory(identifier: "TASK", actions: [
            UNNotificationAction(identifier: "START", title: "Начать фокус", options: [.foreground]),
            UNNotificationAction(identifier: "SNOOZE", title: "Через 10 минут", options: []),
            UNNotificationAction(identifier: "COMPLETE", title: "Завершить", options: [])
        ], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }
    func requestPermission() async -> Bool {
        do { return try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { onError?(error.localizedDescription); return false }
    }
    func sync(tasks: [IslandTask]) {
        let requests: [UNNotificationRequest] = tasks.compactMap { task in
            guard !task.isCompleted, let date = task.reminderAt, date > Date() else { return nil }
            let content = UNMutableNotificationContent()
            content.title = "Пора заняться задачей"; content.body = task.title
            content.sound = .default; content.categoryIdentifier = "TASK"
            content.userInfo = ["taskID": task.id.uuidString]
            return .init(identifier: "task.\(task.id)", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false))
        }
        replace(prefix: "task.", requests: requests)
    }
    func scheduleFocus(_ focus: FocusSession?, taskTitle: String) {
        var requests: [UNNotificationRequest] = []
        if let focus, let deadline = focus.deadline, deadline > Date() {
            let content = UNMutableNotificationContent()
            content.title = "Фокус-сессия завершена"; content.body = taskTitle; content.sound = .default
            requests.append(.init(identifier: "focus.end", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)))
        }
        replace(prefix: "focus.", requests: requests)
    }
    private func replace(prefix: String, requests: [UNNotificationRequest]) {
        queue.async { [self] in
            let revision = (revisions[prefix] ?? 0) + 1
            revisions[prefix] = revision
            center.getNotificationSettings { [self] settings in
                center.getPendingNotificationRequests { [self] previous in
                    queue.async { [self] in
                        // A slower callback must never restore a cancelled or edited reminder.
                        guard revisions[prefix] == revision else { return }
                        center.removePendingNotificationRequests(withIdentifiers: previous.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier))
                        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
                        for request in requests {
                            center.add(request) { [weak self] error in
                                if let error { self?.onError?(error.localizedDescription) }
                            }
                        }
                    }
                }
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let raw = response.notification.request.content.userInfo["taskID"] as? String, let id = UUID(uuidString: raw) {
            onAction?(response.actionIdentifier, id)
        }
        completionHandler()
    }
}
