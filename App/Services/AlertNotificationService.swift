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
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in
                continuation.resume()
            }
        }
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
        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }
}
