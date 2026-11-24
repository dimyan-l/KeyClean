import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    exit(runSelfTest())
}
if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
    MainActor.assumeIsolated { renderImages(to: arguments[index + 1]) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
