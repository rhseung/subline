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
            CommandGroup(after: .newItem) {
                Divider()
                Button("데이터 내보내기...") {
                    store.exportData()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("데이터 가져오기...") {
                    store.importData()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
}
