import SwiftUI
import VistoCore

@main
struct VistoWatchApp: App {
    @ObservedObject private var model = WatchModel.shared
    var body: some Scene {
        WindowGroup {
            WatchHome(model: model).task { model.start() }
        }
    }
}
