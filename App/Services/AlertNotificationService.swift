import Foundation
import UserNotifications

@MainActor
protocol AlertNotificationSending {
    func requestAuthorization() async
    func send(title: String, body: String) async
}

@MainActor
final class UserNotificationService: AlertNotificationSending {
    private lazy var center = UNUserNotificationCenter.current()

    init() {}

    init(center: UNUserNotificationCenter) {
        self.center = center
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func send(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        try? await center.add(request)
    }
}
