import ApplicationServices
import ScreenCaptureKit
import UniformTypeIdentifiers

struct DesktopDriver {
    private let title: AXUIElement
    private let reviewed: AXUIElement
    private let save: AXUIElement
    private let receipt: AXUIElement

    init?(root: AXUIElement) {
        guard let title = Self.find(in: root, role: kAXTextFieldRole, identifier: "draft-title"),
              let reviewed = Self.find(in: root, role: kAXCheckBoxRole, identifier: "draft-reviewed"),
              let save = Self.find(in: root, role: kAXButtonRole, identifier: "draft-save"),
              let receipt = Self.find(in: root, role: kAXStaticTextRole, identifier: "draft-receipt") else { return nil }
        self.title = title
        self.reviewed = reviewed
        self.save = save
        self.receipt = receipt
    }

    func observe() -> FormState? {
        guard let titleValue = Self.attribute(title, kAXValueAttribute) as? String,
              let reviewedValue = Self.attribute(reviewed, kAXValueAttribute) as? NSNumber,
              let saveEnabled = Self.attribute(save, kAXEnabledAttribute) as? NSNumber,
              let receiptValue = Self.attribute(receipt, kAXValueAttribute) as? String else { return nil }
        return FormState(title: titleValue, reviewed: reviewedValue.boolValue,
                         canSave: saveEnabled.boolValue, receipt: receiptValue)
    }

    func perform(_ action: FormAction) throws {
        let result: AXError
        switch action {
        case .enterTitle(let value):
            result = AXUIElementSetAttributeValue(title, kAXValueAttribute as CFString, value as CFString)
        case .markReviewed:
            result = AXUIElementPerformAction(reviewed, kAXPressAction as CFString)
        case .saveDraft:
            result = AXUIElementPerformAction(save, kAXPressAction as CFString)
        }
        guard result == .success else { throw DemoError("\(action) failed with AX error \(result.rawValue).") }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return result == .success ? value : nil
    }

    private static func find(in element: AXUIElement, role: String, identifier: String, depth: Int = 0) -> AXUIElement? {
        guard depth <= 10 else { return nil }
        if (attribute(element, kAXRoleAttribute) as? String) == role,
           (attribute(element, kAXIdentifierAttribute) as? String) == identifier { return element }
        let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        for child in children {
            if let found = find(in: child, role: role, identifier: identifier, depth: depth + 1) { return found }
        }
        return nil
    }
}

func captureWindow(pid: pid_t, title: String, to url: URL) async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    guard let window = content.windows.first(where: {
        $0.owningApplication?.processID == pid && $0.title == title
    }) else {
        throw DemoError("ScreenCaptureKit could not find the form window. Keep it visible and retry.")
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
    guard CGImageDestinationFinalize(destination) else { throw DemoError("Could not write the PNG file.") }
}
