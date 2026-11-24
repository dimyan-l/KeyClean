import AppKit
import ApplicationServices
import SwiftUI

/// `--selftest`: проверка на безобидной клавише F20, которой нет на клавиатуре Mac.
func runSelfTest() -> Int32 {
    guard AXIsProcessTrusted() else {
        print("✗ Нет разрешения «Универсальный доступ»")
        return 1
    }
    // Счётчик в куче: его меняет колбэк, и компилятор не должен считать значение неизменным.
    let delivered = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    delivered.pointee = 0
    let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    guard let listener = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
        eventsOfInterest: mask,
        callback: { _, type, event, refcon in
            if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 90 {
                refcon!.assumingMemoryBound(to: Int.self).pointee += 1
            }
            return Unmanaged.passUnretained(event)
        },
        userInfo: delivered
    ) else {
        print("✗ Не удалось создать контрольный перехват")
        return 1
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, listener, 0), .commonModes)
    CGEvent.tapEnable(tap: listener, enable: true)

    func pressF20() {
        for isDown in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: 90, keyDown: isDown)?.post(tap: .cghidEventTap)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    }

    pressF20()
    let withoutBlock = delivered.pointee

    let mappingBefore = CapsLockGuard.currentMapping()
    let blocker = KeyboardBlocker()
    guard blocker.start() else {
        print("✗ Не удалось включить блокировку")
        return 1
    }
    let capsSkipped = !blocker.capsLockGuarded
    let capsRemapped = capsSkipped || CapsLockGuard.currentMapping().contains { $0["HIDKeyboardModifierMappingSrc"] == 0x700000039 && $0["HIDKeyboardModifierMappingDst"] == 0x70000006F }
    delivered.pointee = 0
    pressF20()
    let withBlock = delivered.pointee
    let blocked = blocker.blockedCount
    blocker.stop()
    let capsRestored = CapsLockGuard.currentMapping() == mappingBefore

    delivered.pointee = 0
    pressF20()
    let afterStop = delivered.pointee

    let passed = withoutBlock == 1 && withBlock == 0 && blocked >= 2 && afterStop == 1 && capsRemapped && capsRestored
    print("\(withoutBlock == 1 ? "✓" : "✗") без блокировки клавиша проходит: \(withoutBlock)")
    print("\(withBlock == 0 && blocked >= 2 ? "✓" : "✗") с блокировкой не проходит: \(withBlock), перехвачено событий: \(blocked)")
    print("\(afterStop == 1 ? "✓" : "✗") после выключения снова проходит: \(afterStop)")
    print(capsSkipped ? "– Caps Lock не тронут: у клавиатур свои назначения клавиш"
                      : "\(capsRemapped ? "✓" : "✗") Caps Lock на время блокировки отключён")
    print("\(capsRestored ? "✓" : "✗") назначения клавиш восстановлены")
    return passed ? 0 : 1
}

/// `--render <папка>`: картинки всех состояний окна и значок приложения.
@MainActor
func renderImages(to folder: String) {
    func save<V: View>(_ view: V, _ name: String, scale: CGFloat = 2) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
    }
    let states: [(String, Bool, Bool)] = [("ready", false, true), ("locked", true, true), ("permission", false, false)]
    for (name, locked, permission) in states {
        save(ContentView(model: AppModel(previewLocked: locked, hasPermission: permission), opaqueBackground: true), "\(name).png")
    }
    save(AppIconView(), "icon.png", scale: 1)
}

struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.62, blue: 1), Color(red: 0.05, green: 0.33, blue: 0.9)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
            Image(systemName: "keyboard")
                .font(.system(size: 400, weight: .regular))
                .foregroundStyle(.white)
            Image(systemName: "sparkles")
                .font(.system(size: 170, weight: .medium))
                .foregroundStyle(.white)
                .offset(x: 245, y: -245)
        }
        .frame(width: 1024, height: 1024)
    }
}
