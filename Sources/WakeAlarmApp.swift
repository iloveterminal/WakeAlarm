import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted when the main window is closing / being dismissed.
    static let wakeAlarmWindowClosing = Notification.Name("wakeAlarmWindowClosing")
}

/// AppKit delegate — keep this off `@MainActor` so NSApplicationDelegate
/// methods are reliably registered with the ObjC runtime.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    weak var controller: AlarmController?
    private var isShuttingDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdownAlarmAndAudio()
    }

    /// Stop beep / release sleep assertion, then quit. Safe to call repeatedly.
    func shutdownAlarmAndAudio() {
        guard !isShuttingDown else {
            // Still try to silence audio if a prior terminate stalled.
            NotificationCenter.default.post(name: .wakeAlarmWindowClosing, object: nil)
            return
        }
        isShuttingDown = true
        NotificationCenter.default.post(name: .wakeAlarmWindowClosing, object: nil)
    }

    func shutdownAndTerminate() {
        shutdownAlarmAndAudio()
        NSApp.terminate(nil)
    }
}

@main
struct WakeAlarmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                .background(WindowCloseInstaller())
                .onAppear {
                    appDelegate.controller = controller
                }
                .onReceive(NotificationCenter.default.publisher(for: .wakeAlarmWindowClosing)) { _ in
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

// MARK: - Window close → stop alarm + quit

/// Chains into SwiftUI's existing NSWindowDelegate so we still get close callbacks.
private final class ChainingWindowDelegate: NSObject, NSWindowDelegate {
    weak var original: NSWindowDelegate?

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return original?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        original
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let original = original,
           original.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))),
           original.windowShouldClose?(sender) == false {
            return false
        }
        AppDelegate.shared?.shutdownAndTerminate()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        AppDelegate.shared?.shutdownAndTerminate()
        original?.windowWillClose?(notification)
    }
}

private struct WindowCloseInstaller: NSViewRepresentable {
    final class Coordinator {
        let proxy = ChainingWindowDelegate()
        private var occlusionObserver: NSObjectProtocol?
        private weak var observedWindow: NSWindow?

        func attach(to window: NSWindow?) {
            guard let window else { return }

            if window.delegate !== proxy {
                // Keep SwiftUI's delegate; forward unknown selectors to it.
                if let current = window.delegate, (current as AnyObject) !== proxy {
                    proxy.original = current
                }
                window.delegate = proxy
            }

            guard observedWindow !== window else { return }
            observedWindow = window

            if let occlusionObserver {
                NotificationCenter.default.removeObserver(occlusionObserver)
            }
            // Some SwiftUI paths order the window out instead of closing it.
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                // Cmd+H hides the app — don't treat that as quit.
                guard !NSApp.isHidden else { return }
                guard let window, !window.isVisible, !window.isMiniaturized else { return }
                // Window ordered out (SwiftUI sometimes skips a real close) and no
                // other titled window remains → stop alarm and quit.
                let otherVisible = NSApp.windows.contains {
                    $0 !== window && $0.isVisible && $0.styleMask.contains(.titled)
                }
                if !otherVisible {
                    AppDelegate.shared?.shutdownAndTerminate()
                }
            }
        }

        deinit {
            if let occlusionObserver {
                NotificationCenter.default.removeObserver(occlusionObserver)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
        }
    }
}
