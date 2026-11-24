import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class AppModel: ObservableObject {
    /// Страховка: если трекпад не сработает, клавиатура вернётся сама.
    static let safetyLimit = 5 * 60

    @Published private(set) var isLocked = false
    @Published private(set) var hasPermission = AXIsProcessTrusted()
    @Published private(set) var secondsLeft = AppModel.safetyLimit
    /// Другая программа включила «защищённый ввод»: в этом режиме macOS не отдаёт клавиши перехвату.
    @Published private(set) var secureInputActive = false

    private let blocker = KeyboardBlocker()
    private var countdown: Timer?
    private var permissionTimer: Timer?
    /// Не даёт экрану погаснуть и включить заставку, пока идёт протирка.
    private var awakeActivity: NSObjectProtocol?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        watchPermission()
        unlockOnSystemEvents()
    }

    /// Для отрисовки картинок без настоящей блокировки.
    init(previewLocked: Bool, hasPermission: Bool) {
        isLocked = previewLocked
        self.hasPermission = hasPermission
        secondsLeft = Self.safetyLimit
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }

    func primaryAction() {
        if !hasPermission {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        } else if isLocked {
            unlock()
        } else {
            lock()
        }
    }

    func unlock() {
        countdown?.invalidate()
        countdown = nil
        blocker.stop()
        if let awakeActivity { ProcessInfo.processInfo.endActivity(awakeActivity) }
        awakeActivity = nil
        isLocked = false
        secureInputActive = false
        secondsLeft = Self.safetyLimit
    }

    private func lock() {
        guard blocker.start() else {
            hasPermission = false
            watchPermission()
            return
        }
        isLocked = true
        secondsLeft = Self.safetyLimit
        secureInputActive = IsSecureEventInputEnabled()
        awakeActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: "Клавиатура заблокирована для протирки"
        )
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.secondsLeft -= 1
            self.secureInputActive = IsSecureEventInputEnabled()
            if self.secondsLeft <= 0 { self.unlock() }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdown = timer
    }

    /// Если экран заблокировался (например, задели кнопку питания с Touch ID), Mac уснул
    /// или переключился пользователь, кнопку «Разблокировать» уже не нажать —
    /// а пароль на экране входа надо вводить с клавиатуры. Поэтому сразу её возвращаем.
    private func unlockOnSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let events: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (workspace, NSWorkspace.sessionDidResignActiveNotification),
            (distributed, Notification.Name("com.apple.screenIsLocked")),
            (distributed, Notification.Name("com.apple.screensaver.didstart")),
        ]
        for (center, name) in events {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.isLocked else { return }
                self.unlock()
            }
            observers.append((center, token))
        }
    }

    private func watchPermission() {
        guard !hasPermission, permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted() else { return }
            timer.invalidate()
            self.permissionTimer = nil
            self.hasPermission = true
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
