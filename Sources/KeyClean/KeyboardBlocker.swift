import AppKit
import ApplicationServices

/// Перехватывает события клавиатуры на самом раннем уровне и выбрасывает их.
/// Трекпад и мышь в маску не входят, поэтому продолжают работать.
final class KeyboardBlocker {
    private(set) var blockedCount = 0
    /// false — у клавиатур свои назначения клавиш, и Caps Lock оставлен как есть (см. CapsLockGuard).
    private(set) var capsLockGuarded = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isActive: Bool { tap != nil }

    /// false — macOS не дала создать перехват: нет разрешения «Универсальный доступ».
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, Self.systemDefined]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let blocker = Unmanaged<KeyboardBlocker>.fromOpaque(refcon!).takeUnretainedValue()
                return blocker.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let newSource = CFMachPortCreateRunLoopSource(nil, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        source = newSource
        blockedCount = 0
        capsLockGuarded = CapsLockGuard.engage()
        return true
    }

    func stop() {
        guard let tap else { return }
        CapsLockGuard.restore()
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS отключает перехват, если посчитает его зависшим. Клавиатура не должна ожить посреди протирки.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case Self.systemDefined:
            // Под этим типом ходят и кнопки мыши, поэтому глушим только яркость, громкость и медиаклавиши.
            guard NSEvent(cgEvent: event)?.subtype.rawValue == Self.mediaKeysSubtype else {
                return Unmanaged.passUnretained(event)
            }
        default:
            break
        }
        blockedCount += 1
        return nil
    }

    private static let systemDefined = CGEventType(rawValue: 14)!   // NX_SYSDEFINED
    private static let mediaKeysSubtype: Int16 = 8                  // NX_SUBTYPE_AUX_CONTROL_BUTTONS
}
