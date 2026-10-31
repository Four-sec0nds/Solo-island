import AppKit
import XCTest
import IslandAccessibility

@MainActor
private final class ActionProbe: NSObject {
    var count = 0
    @objc func activate(_ sender: Any?) { count += 1 }
}

final class NativeAccessibilityTests: XCTestCase {
    func testPressInvokesTheNativeActionAndRespectsDisabledState() async {
        await MainActor.run {
            _ = NSApplication.shared
            let probe = ActionProbe()
            let button = NSButton(title: "Probe", target: probe, action: #selector(ActionProbe.activate(_:)))
            XCTAssertEqual(SIAXRole(button), "AXButton")
            XCTAssertTrue(SIAXPress(button))
            XCTAssertEqual(probe.count, 1)
            button.isEnabled = false
            XCTAssertFalse(SIAXPress(button))
            XCTAssertEqual(probe.count, 1)
        }
    }

    func testModernTextFieldMetadataIsReadable() async {
        await MainActor.run {
            _ = NSApplication.shared
            let field = NSTextField(string: "Draft")
            XCTAssertEqual(SIAXRole(field), "AXTextField")
            XCTAssertTrue(SIAXText(field).contains("Draft"))
            XCTAssertFalse(SIAXFocus(NSObject()))
        }
    }
}
