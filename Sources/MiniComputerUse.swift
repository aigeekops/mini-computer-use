import AppKit
import ApplicationServices

@main
@MainActor
struct MiniComputerUse {
    static let targetTitle = "Mini Computer Use Target"

    static func main() async {
        // Stream progress when Electron reads stdout through a pipe.
        setlinebuf(stdout)
        do {
            switch Array(CommandLine.arguments.dropFirst()) {
            case ["status"]:
                print("Accessibility: \(AXIsProcessTrusted())")
                print("Screen recording: \(CGPreflightScreenCaptureAccess())")
            case ["request-accessibility"]:
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                print("Accessibility: \(AXIsProcessTrustedWithOptions([key: true] as CFDictionary))")
            case ["request-screen"]:
                print("Screen recording: \(CGRequestScreenCaptureAccess())")
            case ["run"]:
                try await run(capture: true)
            case ["run", "--ax-only"]:
                try await run(capture: false)
            default:
                throw DemoError("Usage: mini-computer-use status | request-accessibility | request-screen | run [--ax-only]")
            }
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run(capture: Bool) async throws {
        guard AXIsProcessTrusted() else {
            throw DemoError("Accessibility permission is off. Enable it in System Settings and retry.")
        }
        if capture {
            guard CGPreflightScreenCaptureAccess() else {
                throw DemoError("Screen recording permission is off. Enable it or run the Accessibility-only demo.")
            }
            // Initialize the helper's window-server connection before filtering a window.
            _ = NSApplication.shared
        }

        let output = URL(fileURLWithPath: "runs", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let draftURL = output.appendingPathComponent("draft.json")

        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let targetURL = executable.deletingLastPathComponent().appendingPathComponent("\(targetTitle).app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--output", draftURL.path]
        let target = try await NSWorkspace.shared.openApplication(at: targetURL, configuration: configuration)
        defer { target.terminate() }

        let root = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        let driver = try await waitFor("the form controls") { DesktopDriver(root: root) }
        var state = try await waitFor("the initial form state", read: driver.observe)
        print("Observed: \(state.receipt). Save enabled: \(state.canSave).")
        if capture {
            try await captureWindow(pid: target.processIdentifier, title: targetTitle, to: output.appendingPathComponent("before.png"))
        }

        for _ in 0..<3 {
            guard let action = try DraftWorkflow.nextAction(from: state) else { break }
            print("Action: \(action)")
            try driver.perform(action)
            state = try await waitFor("\(action) to take effect") {
                guard let observed = driver.observe(),
                      action.tookEffect(in: observed, goal: DraftWorkflow.goal) else { return nil }
                return observed
            }
            print("Observed: title=\(state.title), reviewed=\(state.reviewed), receipt=\(state.receipt)")
        }

        guard state.receipt == DraftWorkflow.receipt(for: DraftWorkflow.goal) else {
            throw DemoError("The form did not return the expected save receipt.")
        }
        try DraftWorkflow.verifyDraft(at: draftURL)
        if capture {
            try await Task.sleep(for: .milliseconds(150))
            try await captureWindow(pid: target.processIdentifier, title: targetTitle, to: output.appendingPathComponent("after.png"))
        }
        print("Verified: \(state.receipt) and draft.json match the goal.")
        print("Output: \(output.path)")
    }

    static func waitFor<Value>(_ description: String, read: () -> Value?) async throws -> Value {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        repeat {
            if let value = read() { return value }
            try await Task.sleep(for: .milliseconds(100))
        } while clock.now < deadline
        throw DemoError("Timed out waiting for \(description).")
    }
}
