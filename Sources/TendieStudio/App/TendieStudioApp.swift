import SwiftUI

@main
struct TendieStudioApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.community)
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
                .onOpenURL { model.importFile($0) }
        }
    }
}
