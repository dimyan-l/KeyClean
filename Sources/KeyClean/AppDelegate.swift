import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var window: NSWindow!
    private var subscription: AnyCancellable?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        CapsLockGuard.restore()
        handleTerminationSignals()
        NSApp.mainMenu = makeMenu()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "KeyClean"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Пока клавиатура выключена, кнопка разблокировки всегда на виду.
        // Видно и поверх полноэкранных программ; свернуть окно в Dock на это время нельзя.
        subscription = model.$isLocked.sink { [weak self] locked in
            guard let window = self?.window else { return }
            window.level = locked ? .floating : .normal
            window.collectionBehavior = locked ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
            window.standardWindowButton(.miniaturizeButton)?.isEnabled = !locked
            if locked {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.orderFrontRegardless()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.unlock()
    }

    /// `kill`/`pkill` завершают процесс мимо applicationWillTerminate, и Caps Lock остался бы переназначенным.
    private func handleTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    private func makeMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Завершить KeyClean", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        return menu
    }
}
