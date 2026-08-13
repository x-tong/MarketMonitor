import AppKit
import SwiftUI

@main
struct MarketMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
