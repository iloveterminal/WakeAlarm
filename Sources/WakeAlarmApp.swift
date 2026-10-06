import AppKit
import SwiftUI

@main
struct WakeAlarmApp: App {
    @StateObject private var controller = AlarmController()

    init() {
        AppFonts.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 640, minHeight: 340)
                .frame(width: 680, height: 360)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // Drop sleep assertion / stop beep if the app is quit while armed or ringing.
                    controller.cancelAlarm()
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 680, height: 360)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
