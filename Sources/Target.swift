import AppKit

@MainActor
final class DraftTitle: NSTextField {
    var onChange: (() -> Void)?

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textField }
    override func accessibilityValue() -> String? { stringValue }
    override func setAccessibilityValue(_ value: Any?) {
        guard let text = value as? String else { return }
        stringValue = text
        onChange?()
    }
}

@MainActor
final class DraftButton: NSButton {
    let accessibilityKind: NSAccessibility.Role

    init(role: NSAccessibility.Role) {
        accessibilityKind = role
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { accessibilityKind }
    override func accessibilityValue() -> Any? {
        accessibilityKind == .checkBox ? NSNumber(value: state.rawValue) : nil
    }
    override func isAccessibilityEnabled() -> Bool { isEnabled }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }
}

@MainActor
final class DraftReceipt: NSTextField {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityValue() -> String? { stringValue }
}

@MainActor
final class Demo: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    let titleField = DraftTitle(frame: .zero)
    let reviewed = DraftButton(role: .checkBox)
    let save = DraftButton(role: .button)
    let receipt = DraftReceipt(frame: .zero)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private var draftURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("mini-computer-use-\(UUID().uuidString).json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.count == 2, arguments.first == "--output" {
            draftURL = URL(fileURLWithPath: arguments[1])
        }

        let heading = NSTextField(labelWithString: "Report draft")
        heading.font = .systemFont(ofSize: 27, weight: .semibold)
        titleField.placeholderString = "Draft title"
        titleField.font = .systemFont(ofSize: 17)
        titleField.delegate = self
        titleField.onChange = { [weak self] in self?.updateSaveButton() }
        titleField.setAccessibilityIdentifier("draft-title")
        titleField.setAccessibilityLabel("Draft title")

        reviewed.setButtonType(.switch)
        reviewed.title = "Mark reviewed"
        reviewed.target = self
        reviewed.action = #selector(reviewChanged)
        reviewed.setAccessibilityIdentifier("draft-reviewed")

        save.title = "Save Draft"
        save.bezelStyle = .rounded
        save.target = self
        save.action = #selector(saveDraft)
        save.setAccessibilityIdentifier("draft-save")

        receipt.isEditable = false
        receipt.isSelectable = false
        receipt.isBezeled = false
        receipt.drawsBackground = false
        receipt.font = .monospacedSystemFont(ofSize: 16, weight: .semibold)
        receipt.stringValue = "Draft not saved"
        receipt.setAccessibilityIdentifier("draft-receipt")

        let stack = NSStackView(views: [heading, titleField, reviewed, save, receipt])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -36),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            titleField.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        updateSaveButton()
        window.title = "Mini Computer Use Target"
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if arguments.first == "--self-test" { selfTest(outputPath: arguments.dropFirst().first) }
    }

    func controlTextDidChange(_ obj: Notification) { updateSaveButton() }

    @objc private func reviewChanged() { updateSaveButton() }

    private func updateSaveButton() {
        save.isEnabled = !titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reviewed.state == .on
            && !receipt.stringValue.hasPrefix("Saved: ")
    }

    @objc private func saveDraft() {
        guard save.isEnabled else { return }
        let draft = Draft(title: titleField.stringValue, reviewed: reviewed.state == .on)
        do {
            let data = try JSONEncoder().encode(draft)
            try data.write(to: draftURL, options: .withoutOverwriting)
            receipt.stringValue = DraftWorkflow.receipt(for: draft)
            receipt.textColor = .systemGreen
            updateSaveButton()
        } catch {
            receipt.stringValue = "Save failed: \(error.localizedDescription)"
            receipt.textColor = .systemRed
        }
    }

    private func state() -> FormState {
        FormState(title: titleField.accessibilityValue() ?? "",
                  reviewed: (reviewed.accessibilityValue() as? NSNumber)?.boolValue ?? false,
                  canSave: save.isAccessibilityEnabled(),
                  receipt: receipt.accessibilityValue() ?? "")
    }

    private func selfTest(outputPath: String?) {
        do {
            guard !state().canSave, !save.accessibilityPerformPress(), state().title.isEmpty,
                  titleField.accessibilityRole() == .textField, reviewed.accessibilityRole() == .checkBox,
                  save.accessibilityRole() == .button, receipt.accessibilityRole() == .staticText else {
                throw DemoError("The initial form state or accessibility roles are incorrect.")
            }
            if let outputPath { try renderContent(to: outputPath, name: "ready.png") }

            var actions: [String] = []
            while let action = try DraftWorkflow.nextAction(from: state()), actions.count < 3 {
                actions.append(action.description)
                switch action {
                case .enterTitle(let title): titleField.setAccessibilityValue(title)
                case .markReviewed:
                    guard reviewed.accessibilityPerformPress() else { throw DemoError("Review press failed.") }
                case .saveDraft:
                    guard save.accessibilityPerformPress() else { throw DemoError("Save press failed.") }
                }
                guard action.tookEffect(in: state(), goal: DraftWorkflow.goal) else {
                    throw DemoError("\(action) did not take effect.")
                }
            }
            guard actions == ["Enter title: Monthly report", "Mark reviewed", "Save draft"],
                  state().receipt == DraftWorkflow.receipt(for: DraftWorkflow.goal) else {
                throw DemoError("The expected actions or receipt are missing.")
            }
            try DraftWorkflow.verifyDraft(at: draftURL)
            try FileManager.default.removeItem(at: draftURL)
            if let outputPath { try renderContent(to: outputPath, name: "done.png") }
            print("Target self-test passed: \(actions.joined(separator: " → ")) → verified draft.json")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private func renderContent(to folder: String, name: String) throws {
        guard let content = window.contentView else { throw DemoError("Missing form content.") }
        content.layoutSubtreeIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw DemoError("Could not render the form.")
        }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw DemoError("Could not encode the rendered form.")
        }
        let path = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(name)
        try png.write(to: path, options: .withoutOverwriting)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
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
