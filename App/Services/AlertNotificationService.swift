import Foundation
import UserNotifications

enum AlertNotificationAuthorizationStatus: Equatable, Sendable {
    case unknown
    case notDetermined
    case authorized
    case denied
}

@MainActor
protocol AlertNotificationSending {
    func authorizationStatus() async -> AlertNotificationAuthorizationStatus
    func requestAuthorization() async throws -> AlertNotificationAuthorizationStatus
    func send(title: String, body: String) async throws
}

@MainActor
final class UserNotificationService: AlertNotificationSending {
    private lazy var center = UNUserNotificationCenter.current()

    init() {}

    init(center: UNUserNotificationCenter) {
        self.center = center
    }

    func authorizationStatus() async -> AlertNotificationAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let status: AlertNotificationAuthorizationStatus
                switch settings.authorizationStatus {
                case .notDetermined: status = .notDetermined
                case .denied: status = .denied
                case .authorized, .provisional, .ephemeral: status = .authorized
                @unknown default: status = .denied
                }
                continuation.resume(returning: status)
            }
        }
    }

    func requestAuthorization() async throws -> AlertNotificationAuthorizationStatus {
        let granted = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Bool, any Error>) in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        return granted ? .authorized : .denied
    }

    func send(title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
