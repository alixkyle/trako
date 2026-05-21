import AppKit
import SwiftUI

@MainActor
final class AppWindowPresenter {
    static let shared = AppWindowPresenter()

    private var dashboardWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var privacyPolicyWindow: NSWindow?

    private init() {}

    func showDashboard(tracker: ActivityTracker, pro: ProAccessController) {
        if dashboardWindow == nil {
            let controller = NSHostingController(
                rootView: DashboardView()
                    .environmentObject(tracker)
                    .environmentObject(pro)
                    .frame(minWidth: 860, minHeight: 620)
            )
            dashboardWindow = makeWindow(
                title: "Trako Dashboard",
                contentViewController: controller,
                size: NSSize(width: 980, height: 700),
                minSize: NSSize(width: 860, height: 620),
                isResizable: true
            )
        }

        show(dashboardWindow)
    }

    func showSettings(tracker: ActivityTracker, pro: ProAccessController) {
        if settingsWindow == nil {
            let rootView = SettingsView()
                .environmentObject(tracker)
                .environmentObject(pro)
                .frame(width: 520, height: 480)

            let controller = NSHostingController(rootView: rootView)
            controller.sizingOptions = [.preferredContentSize]

            settingsWindow = makeWindow(
                title: "Trako Settings",
                contentViewController: controller,
                size: NSSize(width: 520, height: 480),
                minSize: NSSize(width: 520, height: 440),
                isResizable: false
            )
        }

        show(settingsWindow)
    }

    func showPrivacyPolicy() {
        if privacyPolicyWindow == nil {
            let controller = NSHostingController(
                rootView: PrivacyPolicyView()
                    .frame(width: 560, height: 420)
            )
            controller.sizingOptions = [.preferredContentSize]
            privacyPolicyWindow = makeWindow(
                title: "Trako Privacy Policy",
                contentViewController: controller,
                size: NSSize(width: 560, height: 420),
                minSize: NSSize(width: 560, height: 360),
                isResizable: true
            )
        }

        show(privacyPolicyWindow)
    }

    private func makeWindow(
        title: String,
        contentViewController: NSViewController,
        size: NSSize,
        minSize: NSSize,
        isResizable: Bool
    ) -> NSWindow {
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if isResizable {
            styleMask.insert(.resizable)
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = contentViewController
        window.minSize = minSize
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func show(_ window: NSWindow?) {
        guard let window else {
            return
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}
