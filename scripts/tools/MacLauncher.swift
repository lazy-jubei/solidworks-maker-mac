import AppKit
import Darwin
import Foundation

guard let script = Bundle.main.url(forResource: "launch", withExtension: "sh") else {
    fputs("SolidWorks launcher script is missing.\n", stderr)
    exit(EXIT_FAILURE)
}

// While this file exists, show its notice (first line title, the rest the message). The launch
// scripts write it when Wine's startup stalls, usually on a macOS privacy prompt; an alert from
// the scripts themselves can't come forward, because macOS holds a background process's alert.
let noticeDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("solidworks-launcher-\(getpid())", isDirectory: true)
try? FileManager.default.createDirectory(at: noticeDirectory, withIntermediateDirectories: true)
let noticeFile = noticeDirectory.appendingPathComponent("notice")

// Keep the native app alive so macOS can attribute the script's file access to it.
let launcher = Process()
launcher.executableURL = URL(fileURLWithPath: "/bin/zsh")
launcher.arguments = [script.path] + Array(CommandLine.arguments.dropFirst())
var environment = ProcessInfo.processInfo.environment
environment["SW_LAUNCHER_NOTICE"] = noticeFile.path
launcher.environment = environment
launcher.terminationHandler = { process in
    DispatchQueue.main.async {
        try? FileManager.default.removeItem(at: noticeDirectory)
        exit(process.terminationStatus)
    }
}

final class Notice: NSObject {
    private var alert: NSAlert?

    @objc func dismiss(_ sender: Any?) {
        alert?.window.orderOut(nil)
    }

    func update() {
        guard let text = try? String(contentsOf: noticeFile, encoding: .utf8) else {
            alert?.window.orderOut(nil)
            alert = nil
            return
        }
        guard alert == nil else { return }
        let lines = text.split(separator: "\n", maxSplits: 1).map(String.init)
        let shown = NSAlert()
        shown.messageText = lines.first ?? "SolidWorks is still starting"
        shown.informativeText = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let button = shown.addButton(withTitle: "OK")
        button.target = self
        button.action = #selector(dismiss(_:))
        shown.layout()
        shown.window.level = .floating
        shown.window.center()
        NSApp.activate(ignoringOtherApps: true)
        shown.window.makeKeyAndOrderFront(nil)
        alert = shown
    }
}

let app = NSApplication.shared
// No Dock icon of its own: SolidWorks keeps the only one.
app.setActivationPolicy(.accessory)
let notice = Notice()
do {
    try launcher.run()
} catch {
    fputs("Could not start the SolidWorks launcher: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in notice.update() }
app.run()
