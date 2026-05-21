import AppKit
import Combine
import SwiftUI

@main
struct TrakoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.tracker)
                .environmentObject(appDelegate.pro)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let tracker = ActivityTracker()
    let pro = ProAccessController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProAccessController.shouldAutoEnableTestingUnlock {
            pro.setTestingUnlocked(true)
        }

        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        subscribeToTracker()
        updateStatusButton()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker.persist()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem = item
    }

    private func configurePopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(tracker)
                .environmentObject(pro)
        )
        popover.contentSize = NSSize(width: 340, height: 520)
        self.popover = popover
    }

    private func subscribeToTracker() {
        tracker.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)
    }

    private func updateStatusButton() {
        guard let button = statusItem?.button else {
            return
        }

        button.image = NSImage(
            systemSymbolName: tracker.isActivelyCounting ? "timer" : "pause.circle",
            accessibilityDescription: tracker.pauseStateDescription
        )
        button.image?.isTemplate = true
        button.title = " \(tracker.todayClockText)"
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
