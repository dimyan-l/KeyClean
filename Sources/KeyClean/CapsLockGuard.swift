import Foundation

/// Caps Lock macOS переключает раньше, чем событие доходит до перехвата, и выбросить его поздно.
/// Поэтому на время блокировки переназначаем его на F20: такую клавишу KeyboardBlocker просто глушит.
enum CapsLockGuard {
    private static let srcKey = "HIDKeyboardModifierMappingSrc"
    private static let dstKey = "HIDKeyboardModifierMappingDst"
    private static let capsLock = 0x700000039
    private static let f20 = 0x70000006F

    /// hidutil без --matching пишет таблицу во все устройства сразу. Если у устройств свои назначения
    /// (например, в Настройках Caps Lock → Escape только для одной клавиатуры), глобальная запись
    /// разнесла бы их повсюду, а restore() потом стёр бы. В таком случае Caps Lock не трогаем.
    @discardableResult
    static func engage() -> Bool {
        let services = mappingPerService()
        guard let first = services.first, services.allSatisfy({ Set($0) == Set(first) }) else { return false }
        let others = first.filter { $0[srcKey] != capsLock }
        apply(others + [[srcKey: capsLock, dstKey: f20]])
        return true
    }

    /// Ничего не запоминает, а убирает своё назначение: так же лечится и аварийное завершение при следующем запуске.
    static func restore() {
        let current = currentMapping()
        let others = current.filter { !($0[srcKey] == capsLock && $0[dstKey] == f20) }
        if others.count != current.count { apply(others) }
    }

    /// hidutil печатает таблицу по всем устройствам, поэтому собираем уникальные пары из её текста.
    static func currentMapping() -> [[String: Int]] {
        pairs(in: hidutil(["property", "--get", "UserKeyMapping"]))
    }

    /// Назначения каждой клавиатуры отдельно: строка устройства начинается с его RegistryID.
    /// Только клавиатуры: датчики (гироскоп, освещённость, мультитач) глобальную запись не принимают
    /// и всегда показывают (null), из-за чего таблицы «различались» бы всегда.
    private static func mappingPerService() -> [[[String: Int]]] {
        let output = hidutil(["property", "--matching", "keyboard", "--get", "UserKeyMapping"])
        var services: [String] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let isServiceLine = line.range(of: "^[0-9a-fA-F]+\\s+UserKeyMapping", options: .regularExpression) != nil
            if isServiceLine {
                services.append(String(line))
            } else if !services.isEmpty {
                services[services.count - 1] += "\n" + line
            }
        }
        return services.map(pairs(in:))
    }

    private static func pairs(in output: String) -> [[String: Int]] {
        let pattern = "\\b\(dstKey) = (\\d+);\\s*\(srcKey) = (\\d+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var result: [[String: Int]] = []
        for match in regex.matches(in: output, range: NSRange(output.startIndex..., in: output)) {
            guard let dst = Range(match.range(at: 1), in: output).flatMap({ Int(output[$0]) }),
                  let src = Range(match.range(at: 2), in: output).flatMap({ Int(output[$0]) }) else { continue }
            let pair = [srcKey: src, dstKey: dst]
            if !result.contains(pair) { result.append(pair) }
        }
        return result
    }

    private static func apply(_ mapping: [[String: Int]]) {
        let data = (try? JSONSerialization.data(withJSONObject: mapping)) ?? Data()
        let list = String(data: data, encoding: .utf8) ?? "[]"
        _ = hidutil(["property", "--set", "{\"UserKeyMapping\":\(list)}"])
    }

    private static func hidutil(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
