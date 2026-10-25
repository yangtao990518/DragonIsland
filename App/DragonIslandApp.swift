import SwiftUI

@main
struct DragonIslandApp: App {
    @StateObject private var store = CompanionStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .preferredColorScheme(.dark)
                .onOpenURL { _ in store.restore() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.restore() }
                }
        }
    }
}
