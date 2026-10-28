import SwiftUI
import VistoCore

@main
struct VistoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = PhoneModel.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if model.code == nil { PairView(model: model) } else { HomeView(model: model, client: model.client) }
            }
            .preferredColorScheme(.dark)
            .task { model.start() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @MainActor in PhoneModel.shared.start() }
        return true
    }
}
