import XCTest

final class OrbitUITests:XCTestCase {
    @MainActor
    private func reveal(_ element:XCUIElement,in app:XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable,"Control should be reachable by scrolling")
    }

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

    @MainActor
    func testNativeSignInAndDownloadShareSheets() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-orbit.endpoint","https://127.0.0.1:18443"]
        app.launch()
        let username = app.textFields["router-username"]
        XCTAssertTrue(username.waitForExistence(timeout:15))
        reveal(username,in:app)
        username.tap()
        username.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.5)).tap()
        username.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:4)+"orbit-test+operator")
        let password = app.secureTextFields["router-password"]
        password.tap(); password.typeText("test &+ unicode ü")
        let save = app.switches["save-login"]
        reveal(save,in:app)
        if save.value as? String == "1" { save.tap() }
        let trust = app.buttons["trust-router"]
        XCTAssertTrue(trust.waitForExistence(timeout:15))
        reveal(trust,in:app); trust.tap()
        let heading = app.webViews.staticTexts["Orbit test workspace"]
        XCTAssertTrue(heading.waitForExistence(timeout:20))
        for title in ["Download test report","Export test case","Download browser report"] {
            let control = title == "Download test report" ? app.webViews.links[title] : app.webViews.buttons[title]
            XCTAssertTrue(control.waitForExistence(timeout:10))
            reveal(control,in:app); control.tap()
            let close = app.buttons["Close"]
            XCTAssertTrue(close.waitForExistence(timeout:15),"\(title) should open the native share sheet")
            let image = XCTAttachment(screenshot:app.screenshot())
            image.name = title; image.lifetime = .keepAlways; add(image)
            close.tap()
        }
        app.webViews.buttons["Connection settings"].tap()
        XCTAssertTrue(app.buttons["Return to workspace"].waitForExistence(timeout:10))
    }
}
