import Foundation
import UserNotifications
import Observation

@MainActor
@Observable
class NotificationRuntimeManager: NSObject {
    static let shared = NotificationRuntimeManager()

    var isAuthorized = false
    

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()
    }

    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()

        let granted = try await center.requestAuthorization(
            options: [.alert, .badge, .sound]
        )

        await MainActor.run {
            self.isAuthorized = granted
        }

    }

    private func setupNotificationCategories() {
        let explorationCompleteCategory = UNNotificationCategory(
            identifier: "EXPLORATION_COMPLETE",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let generalCategory = UNNotificationCategory(
            identifier: "GENERAL",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            explorationCompleteCategory,
            generalCategory
        ])
    }
}

// MARK: - UNUserNotificationCenterDelegate
@MainActor
extension NotificationRuntimeManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        await OperationHistoryManager.shared.logOperation(
            .appLaunch,
            metadata: [
                "trigger": "notification",
                "identifier": identifier
            ]
        )
    }
}
