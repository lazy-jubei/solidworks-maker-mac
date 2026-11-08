// The guided installer's window. installer-ui.zsh compiles this locally with the Command
// Line Tools' swiftc, so nothing is downloaded or needs signing, and Gatekeeper does not
// quarantine it. The window runs scripts/install-guided.sh with SW_INSTALLER_UI=app:
// lines starting with "@@sw<TAB>" are prompts and progress, every other line goes to the
// built-in terminal pane, and answers are written back on the script's standard input.
// Quitting stops the script's whole process group, including the dashboard browser.
import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers

enum Step: Int, CaseIterable, Identifiable {
    case wine, launcher, components, solidworks, finish
    var id: Int { rawValue }

    init?(key: String) {
        switch key {
        case "wine": self = .wine
        case "launcher": self = .launcher
        case "components": self = .components
        case "solidworks": self = .solidworks
        case "finish": self = .finish
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .wine: return "Prepare Wine"
        case .launcher: return "Download the Launcher"
        case .components: return "Install components"
        case .solidworks: return "Install SOLIDWORKS"
        case .finish: return "Finish"
        }
    }
}

enum Page: Equatable {
    case working
    case message(title: String, text: String, button: String, waitFor: String)
    case url(text: String)
    case msi(text: String)
    case failed(stage: String)
    case finished(text: String)
}

struct LogLine: Identifiable {
    let id: Int
    let text: String
}

final class Installer: ObservableObject {
    @Published var page: Page = .working
    @Published var step: Step = .wine
    @Published var stage = "Starting"
    @Published var status = ""
    @Published var log: [LogLine] = []
    @Published var showTerminal = false
    @Published var field = ""
    @Published var msiFound = false
    @Published var waitFound = false

    let root: URL?
    private(set) var group: pid_t = 0
    private var running = false
    private var input: Int32 = -1
    private var output: FileHandle?
    private var partial = Data()
    private var nextLine = 0
    private var failedStage: String?
    private var finishedText: String?

    init(root: URL?) { self.root = root }

    var finished: Bool { if case .finished = page { return true } else { return false } }
    var failed: Bool { if case .failed = page { return true } else { return false } }
    var busy: Bool { running && page == .working }

    func start() {
        guard let root, FileManager.default.fileExists(atPath: root.appendingPathComponent("scripts/install-guided.sh").path) else {
            append("Could not find the SOLIDWORKS Maker on Mac folder. Run scripts/install-guided.sh from Terminal.")
            page = .failed(stage: "finding the installation folder")
            showTerminal = true
            return
        }
        page = .working
        stage = "Starting"
        status = ""
        failedStage = nil
        finishedText = nil
        var inFDs: [Int32] = [0, 0]
        var outFDs: [Int32] = [0, 0]
        guard pipe(&inFDs) == 0, pipe(&outFDs) == 0 else { return }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, inFDs[0], 0)
        posix_spawn_file_actions_adddup2(&actions, outFDs[1], 1)
        posix_spawn_file_actions_adddup2(&actions, outFDs[1], 2)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        // Its own process group, so quitting can stop the script and everything it started.
        posix_spawnattr_setpgroup(&attributes, 0)
        var all = sigset_t()
        sigfillset(&all)
        posix_spawnattr_setsigdefault(&attributes, &all)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attributes, &none)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF
                                                     | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var environment = ProcessInfo.processInfo.environment
        environment["SW_INSTALLER_UI"] = "app"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if environment["LANG"] == nil { environment["LANG"] = "en_US.UTF-8" }
        let script = root.appendingPathComponent("scripts/install-guided.sh").path
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/zsh"), strdup(script), nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        var child: pid_t = 0
        let result = posix_spawn(&child, "/bin/zsh", &actions, &attributes, argv, envp)
        argv.forEach { free($0) }
        envp.forEach { free($0) }
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attributes)
        close(inFDs[0])
        close(outFDs[1])
        guard result == 0 else {
            close(inFDs[1])
            close(outFDs[0])
            append("Could not start the installer: \(String(cString: strerror(result)))")
            page = .failed(stage: "starting the installer")
            return
        }
        group = child
        running = true
        input = inFDs[1]
        let handle = FileHandle(fileDescriptor: outFDs[0], closeOnDealloc: true)
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil }
            DispatchQueue.main.async { self?.receive(data) }
        }
        output = handle
        DispatchQueue.global().async { [weak self] in
            var status: Int32 = 0
            while waitpid(child, &status, 0) < 0 && errno == EINTR {}
            let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            // Let the last output arrive before showing the result.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.exited(code) }
        }
    }

    private func receive(_ data: Data) {
        if data.isEmpty {
            if !partial.isEmpty { handle(String(decoding: partial, as: UTF8.self)) }
            partial.removeAll()
            return
        }
        partial.append(data)
        while let newline = partial.firstIndex(of: 0x0A) {
            let line = partial[partial.startIndex..<newline]
            partial.removeSubrange(partial.startIndex...newline)
            handle(String(decoding: line, as: UTF8.self))
        }
    }

    private func handle(_ raw: String) {
        // Progress meters redraw with carriage returns; keep what was drawn last.
        let line = raw.split(separator: "\r", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        guard line.hasPrefix("@@sw\t") else {
            append(line)
            return
        }
        let fields = line.dropFirst(5).split(separator: "\t", omittingEmptySubsequences: false).map { unescape(String($0)) }
        func at(_ index: Int) -> String { index < fields.count ? fields[index] : "" }
        switch at(0) {
        case "stage":
            if let next = Step(key: at(1)) { step = next }
            stage = at(2)
            status = ""
        case "notify":
            status = at(1)
        case "message":
            page = .message(title: at(2), text: at(3), button: at(1), waitFor: at(4))
            checkWait()
        case "url":
            field = at(1)
            page = .url(text: at(2))
        case "msi":
            field = at(1)
            page = .msi(text: at(2))
            checkMSI()
        case "failed":
            failedStage = at(1)
        case "finished":
            finishedText = at(1)
        default:
            append(line)
        }
    }

    private func unescape(_ text: String) -> String {
        var result = ""
        var escaped = false
        for character in text {
            if escaped {
                switch character {
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    private func append(_ text: String) {
        log.append(LogLine(id: nextLine, text: text))
        nextLine += 1
        if log.count > 4000 { log.removeFirst(log.count - 3000) }
    }

    private func exited(_ code: Int32) {
        running = false
        if input >= 0 { close(input); input = -1 }
        if code == 0 {
            step = .finish
            page = .finished(text: finishedText ?? "Setup is complete.")
        } else if code != 130 && code != 143 {
            page = .failed(stage: failedStage ?? stage)
            showTerminal = true
        }
    }

    func reply(_ answer: String) {
        page = .working
        guard input >= 0 else { return }
        let bytes = Array((answer + "\n").utf8)
        _ = bytes.withUnsafeBufferPointer { write(input, $0.baseAddress, $0.count) }
    }

    func checkMSI() {
        let path = (field as NSString).expandingTildeInPath
        var directory: ObjCBool = false
        msiFound = path.lowercased().hasSuffix(".msi")
            && FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue
    }

    // A message can name a file (the SOLIDWORKS shortcut) that must exist before continuing.
    func checkWait() {
        guard case let .message(_, _, _, waitFor) = page else { return }
        waitFound = waitFor.isEmpty || FileManager.default.fileExists(atPath: waitFor)
    }

    func browseMSI() {
        let panel = NSOpenPanel()
        panel.message = "Select the 3DEXPERIENCE Launcher installer (.msi)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let msi = UTType(filenameExtension: "msi") { panel.allowedContentTypes = [msi] }
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url {
            field = url.path
            checkMSI()
        }
    }

    func retry() {
        log.removeAll()
        start()
    }

    // Stops the script and everything it started (the dashboard browser too). After a
    // successful setup nothing is stopped, so SOLIDWORKS keeps running.
    func stop(then done: @escaping () -> Void) {
        let target = group
        guard target != 0, !finished else { done(); return }
        if input >= 0 { close(input); input = -1 }
        kill(-target, SIGTERM)
        DispatchQueue.global().async {
            for _ in 0..<40 where kill(-target, 0) == 0 { usleep(100_000) }
            kill(-target, SIGKILL)
            DispatchQueue.main.async(execute: done)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let installer: Installer
    private var closingWindow = false

    override init() {
        let arguments = CommandLine.arguments
        var root: URL?
        if let index = arguments.firstIndex(of: "--root"), index + 1 < arguments.count {
            root = URL(fileURLWithPath: arguments[index + 1])
        } else {
            // Built into <project>/tools/, so the project is two levels up.
            root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        }
        installer = Installer(root: root)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            self?.closingWindow = true
        }
        NSApp.activate(ignoringOtherApps: true)
        installer.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if installer.busy && !closingWindow {
            let alert = NSAlert()
            alert.messageText = "Stop setup?"
            alert.informativeText = "The current step stops. Open the installer again to continue: completed steps are skipped."
            alert.addButton(withTitle: "Stop Setup")
            alert.addButton(withTitle: "Keep Running")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        installer.stop { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

@main
struct InstallerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("SOLIDWORKS Maker on Mac", id: "installer") {
            ContentView(installer: delegate.installer)
                .frame(minWidth: 780, idealWidth: 820, minHeight: 500, idealHeight: 560)
        }
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct ContentView: View {
    @ObservedObject var installer: Installer

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(installer: installer)
                .frame(width: 230)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            VStack(spacing: 0) {
                PageView(installer: installer)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                TerminalPane(installer: installer)
                Divider()
                BottomBar(installer: installer)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
    }
}

struct Sidebar: View {
    @ObservedObject var installer: Installer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SOLIDWORKS Maker on Mac")
                .font(.headline)
                .padding(.bottom, 10)
            ForEach(Step.allCases) { step in
                HStack(spacing: 10) {
                    icon(for: step).frame(width: 18, height: 18)
                    Text(step.title)
                        .fontWeight(step == installer.step && !installer.finished ? .semibold : .regular)
                        .foregroundStyle(step.rawValue > installer.step.rawValue ? .secondary : .primary)
                }
            }
        }
        .padding(22)
    }

    @ViewBuilder private func icon(for step: Step) -> some View {
        if installer.finished || step.rawValue < installer.step.rawValue {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if step.rawValue > installer.step.rawValue {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        } else if installer.failed {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else if installer.busy {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "arrow.right.circle.fill").foregroundStyle(Color.accentColor)
        }
    }
}

struct PageView: View {
    @ObservedObject var installer: Installer
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch installer.page {
            case .working:
                heading(installer.step.title)
                Text(sentence(installer.stage) + "…").font(.title3)
                ProgressView().progressViewStyle(.linear)
                if !installer.status.isEmpty {
                    Text(installer.status).foregroundStyle(.secondary)
                }
                if !installer.showTerminal, let last = installer.log.last(where: { !$0.text.isEmpty }) {
                    Text(last.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            case let .message(title, text, _, waitFor):
                heading(title.isEmpty ? installer.step.title : title)
                paragraph(text)
                if !waitFor.isEmpty {
                    if installer.waitFound {
                        Label("SOLIDWORKS is installed.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for the SOLIDWORKS installer to finish. Continue becomes available when it has.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            case let .url(text):
                heading("Sign in to SOLIDWORKS for Makers")
                paragraph(text)
                TextField("https://", text: $installer.field)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
            case let .msi(text):
                heading("Download the 3DEXPERIENCE Launcher")
                paragraph(text)
                HStack {
                    TextField("Launcher installer (.msi)", text: $installer.field)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { installer.checkMSI() }
                    Button("Browse…") { installer.browseMSI() }
                }
                if installer.msiFound {
                    Label("Found \((installer.field as NSString).lastPathComponent)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for the download. Continue becomes available when the file is found.")
                            .foregroundStyle(.secondary)
                    }
                }
            case let .failed(stage):
                Label("Setup stopped", systemImage: "exclamationmark.triangle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.red)
                paragraph("Setup stopped while \(stage). The terminal below shows the details.\n\nFix the problem, then click Try Again: completed steps are skipped.")
            case let .finished(text):
                Label("Setup complete", systemImage: "checkmark.seal.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.green)
                paragraph(text)
            }
        }
        .onReceive(poll) { _ in
            if case .msi = installer.page { installer.checkMSI() }
            if case .message = installer.page { installer.checkWait() }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.title2.bold())
    }

    private func paragraph(_ text: String) -> some View {
        Text(text).font(.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }

    private func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

struct TerminalPane: View {
    @ObservedObject var installer: Installer

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { installer.showTerminal.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(installer.showTerminal ? 90 : 0))
                        .font(.caption.weight(.semibold))
                    Image(systemName: "terminal")
                    Text("Terminal")
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            if installer.showTerminal {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(installer.log) { line in
                                Text(line.text.isEmpty ? " " : line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.88))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                        .padding(10)
                        .textSelection(.enabled)
                    }
                    .background(Color(white: 0.11))
                    .onAppear { if let last = installer.log.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                    .onReceive(installer.$log) { log in
                        if let last = log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .frame(height: 200)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

struct BottomBar: View {
    @ObservedObject var installer: Installer

    var body: some View {
        HStack {
            Button(installer.finished ? "Close" : "Quit") { NSApp.terminate(nil) }
            Spacer()
            switch installer.page {
            case .working:
                EmptyView()
            case let .message(_, _, button, _):
                primary(button) { installer.reply("ok") }
                    .disabled(!installer.waitFound)
            case .url:
                primary("Open Browser") { installer.reply(installer.field.trimmingCharacters(in: .whitespaces)) }
                    .disabled(!installer.field.trimmingCharacters(in: .whitespaces).hasPrefix("https://"))
            case .msi:
                primary("Continue") { installer.reply((installer.field as NSString).expandingTildeInPath) }
                    .disabled(!installer.msiFound)
            case .failed:
                primary("Try Again") { installer.retry() }
            case .finished:
                EmptyView()
            }
        }
        .controlSize(.large)
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
    }
}
