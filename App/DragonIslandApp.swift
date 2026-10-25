import SwiftUI

@main
struct DragonIslandApp: App {
    @StateObject private var store = CompanionStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "dark"

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--appearance-light") { UserDefaults.standard.set("light", forKey: "appearance") }
        if ProcessInfo.processInfo.arguments.contains("--appearance-dark") { UserDefaults.standard.set("dark", forKey: "appearance") }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .preferredColorScheme(appearance == "light" ? .light : .dark)
                .onOpenURL { _ in store.restore() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.restore() }
                }
        }
    }
}
