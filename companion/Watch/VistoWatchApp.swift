import SwiftUI
import VistoCore

@main
struct VistoWatchApp: App {
    @StateObject private var model = WatchModel()
    var body: some Scene {
        WindowGroup {
            WatchHome(model: model).task { model.start() }
        }
    }
}
