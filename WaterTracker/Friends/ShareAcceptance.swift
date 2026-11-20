import CloudKit
import UIKit

/// Lets the app receive friend invitations. When someone taps an invitation
/// link, iOS opens the app and hands the invitation to the scene delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareSceneDelegate.self
        return configuration
    }
}

final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// The app was not running when the invitation was tapped.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { await FriendsModel.shared.accept(metadata) }
        }
    }

    /// The app was already running.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { await FriendsModel.shared.accept(cloudKitShareMetadata) }
    }
}
