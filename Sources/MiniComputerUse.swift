import AppKit
import ApplicationServices
import ScreenCaptureKit
import UniformTypeIdentifiers

struct DemoError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    init(_ message: String) {
        self.message = message
    }
}

@main
@MainActor
struct MiniComputerUse {
    static let targetTitle = "Mini Computer Use Target"

    static func main() async {
        do {
            switch Array(CommandLine.arguments.dropFirst()) {
            case ["status"]:
                print("Accessibility: \(AXIsProcessTrusted())")
                print("Screen recording: \(CGPreflightScreenCaptureAccess())")
            case ["request-accessibility"]:
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
                print("Accessibility: \(trusted)")
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
            throw DemoError("Accessibility permission is off. Run request-accessibility, allow the app in System Settings, and retry.")
        }
        if capture && !CGPreflightScreenCaptureAccess() {
            throw DemoError("Screen recording permission is off. Run request-screen and allow the app, or use run --ax-only.")
        }

        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let targetURL = executable.deletingLastPathComponent().appendingPathComponent("\(targetTitle).app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        let target = try await NSWorkspace.shared.openApplication(at: targetURL, configuration: configuration)
        defer { target.terminate() }
        let pid = target.processIdentifier
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.5)

        let checkbox = try await waitFor("the Mark done checkbox") {
            findCheckbox(in: root, depth: 0)
        }
        guard checkboxValue(checkbox) == 0 else {
            throw DemoError("Expected the checkbox to start unchecked.")
        }
        print("Before: AXCheckBox Mark done = 0")

        var output: URL?
        if capture {
            let folder = URL(fileURLWithPath: "captures", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            output = folder
            try await captureWindow(pid: pid, to: folder.appendingPathComponent("before.png"))
        }

        let result = AXUIElementPerformAction(checkbox, kAXPressAction as CFString)
        guard result == .success else {
            throw DemoError("AXPress failed with code \(result.rawValue).")
        }
        print("Action: AXPress")

        _ = try await waitFor("the checkbox value to become 1") {
            checkboxValue(checkbox) == 1 ? true : nil
        }
        print("Verified: AXCheckBox Mark done = 1")

        if let output {
            // Give AppKit a frame to repaint after its accessibility value changes.
            try await Task.sleep(for: .milliseconds(150))
            try await captureWindow(pid: pid, to: output.appendingPathComponent("after.png"))
            print("Screenshots: \(output.path)")
        }
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return result == .success ? value : nil
    }

    static func findCheckbox(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= 10 else { return nil }
        if (attribute(element, kAXRoleAttribute) as? String) == (kAXCheckBoxRole as String),
           (attribute(element, kAXIdentifierAttribute) as? String) == "mark-done" {
            return element
        }
        let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        for child in children {
            if let found = findCheckbox(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    static func checkboxValue(_ element: AXUIElement) -> Int? {
        (attribute(element, kAXValueAttribute) as? NSNumber)?.intValue
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

    static func captureWindow(pid: pid_t, to url: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: {
            $0.owningApplication?.processID == pid && $0.title == targetTitle
        }) else {
            throw DemoError("ScreenCaptureKit could not find the demo window. Keep it visible and retry.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let settings = SCStreamConfiguration()
        settings.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        settings.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        settings.ignoreShadowsSingleWindow = true
        settings.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: settings)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw DemoError("Could not create the PNG file.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DemoError("Could not write the PNG file.")
        }
    }
}
