import SwiftUI

@main
struct SublineApp: App {
    @StateObject private var store = SubscriptionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("새 구독") {
                    store.addSubscription()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
