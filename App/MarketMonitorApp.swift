import SwiftUI

@main
struct MarketMonitorApp: App {
    @StateObject private var store = MarketStore()

    var body: some Scene {
        MenuBarExtra {
            MarketPopoverView()
                .environmentObject(store)
                .frame(width: 380)
        } label: {
            StatusBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}
