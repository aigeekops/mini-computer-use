import AppKit

@MainActor
final class DemoCheckbox: NSButton {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilityValue() -> Any? { NSNumber(value: state.rawValue) }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }
}

@MainActor
final class Demo: NSObject, NSApplicationDelegate {
    let status = NSTextField(labelWithString: "READY")
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 250),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let title = NSTextField(labelWithString: "Mini Computer Use")
        title.font = .systemFont(ofSize: 27, weight: .semibold)
        status.font = .monospacedSystemFont(ofSize: 42, weight: .bold)
        status.textColor = .secondaryLabelColor
        let checkbox = DemoCheckbox(frame: .zero)
        checkbox.setButtonType(.switch)
        checkbox.title = "Mark done"
        checkbox.target = self
        checkbox.action = #selector(markDone(_:))
        checkbox.font = .systemFont(ofSize: 18)
        checkbox.setAccessibilityIdentifier("mark-done")
        let stack = NSStackView(views: [title, status, checkbox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 40),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
        window.title = "Mini Computer Use Target"
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--self-test" { selfTest(checkbox, outputPath: arguments.dropFirst().first) }
    }

    @objc private func markDone(_ sender: NSButton) {
        status.stringValue = sender.state == .on ? "DONE" : "READY"
        status.textColor = sender.state == .on ? .systemGreen : .secondaryLabelColor
    }

    private func selfTest(_ checkbox: NSButton, outputPath: String?) {
        guard checkbox.accessibilityIdentifier() == "mark-done",
              checkbox.accessibilityRole() == .checkBox,
              (checkbox.accessibilityValue() as? NSNumber)?.intValue == 0,
              status.stringValue == "READY" else {
            print("Unexpected initial state: role=\(String(describing: checkbox.accessibilityRole())), identifier=\(String(describing: checkbox.accessibilityIdentifier())), value=\(checkbox.state.rawValue), label=\(status.stringValue)")
            exit(1)
        }
        if let outputPath { renderContent(to: outputPath, name: "ready.png") }
        guard checkbox.accessibilityPerformPress(),
              (checkbox.accessibilityValue() as? NSNumber)?.intValue == 1,
              status.stringValue == "DONE" else {
            print("Accessibility press did not update the checkbox and status label.")
            exit(1)
        }
        if let outputPath { renderContent(to: outputPath, name: "done.png") }
        print("Target self-test passed: READY → DONE")
        exit(0)
    }

    private func renderContent(to folder: String, name: String) {
        guard let content = window.contentView else { exit(1) }
        content.layoutSubtreeIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { exit(1) }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        do {
            let path = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(name)
            try png.write(to: path, options: .withoutOverwriting)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
@MainActor
enum TargetApp {
    static func main() {
        let application = NSApplication.shared
        let demo = Demo()
        application.setActivationPolicy(.regular)
        application.delegate = demo
        application.run()
    }
}
