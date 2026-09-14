import XCTest

final class OrbitUITests:XCTestCase {
    @MainActor
    func testConnectionScreenAndAddressValidation() throws {
        let app = XCUIApplication()
        app.launch()
        let address = app.textFields["router-address"]
        XCTAssertTrue(address.waitForExistence(timeout:10))
        let image = XCTAttachment(screenshot:app.screenshot())
        image.name = "Orbit connection screen"; image.lifetime = .keepAlways; add(image)
        address.tap()
        address.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.5)).tap()
        let current = (address.value as? String) ?? ""
        address.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:current.count) + "http://192.168.8.1")
        let connect = app.buttons["connect-router"]
        if !connect.isHittable { app.swipeUp() }
        connect.tap()
        let message = app.staticTexts["connection-message"]
        XCTAssertTrue(message.waitForExistence(timeout:5))
        XCTAssertTrue(message.label.contains("HTTPS"))
    }
}
