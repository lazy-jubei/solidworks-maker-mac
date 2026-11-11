import Darwin
import Foundation

guard let script = Bundle.main.url(forResource: "launch", withExtension: "sh") else {
    fputs("SolidWorks launcher script is missing.\n", stderr)
    exit(EXIT_FAILURE)
}

// Keep the native app alive so macOS can attribute the script's file access to it.
let launcher = Process()
launcher.executableURL = URL(fileURLWithPath: "/bin/zsh")
launcher.arguments = [script.path] + Array(CommandLine.arguments.dropFirst())
do {
    try launcher.run()
    launcher.waitUntilExit()
    exit(launcher.terminationStatus)
} catch {
    fputs("Could not start the SolidWorks launcher: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
