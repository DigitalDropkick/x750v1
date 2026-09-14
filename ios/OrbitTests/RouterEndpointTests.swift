import XCTest
@testable import Orbit

final class RouterEndpointTests:XCTestCase {
    func testCanonicalOriginAndConsole() throws {
        let endpoint = try RouterEndpoint(" https://Router.LOCAL:443/ ")
        XCTAssertEqual(endpoint.key,"https://router.local")
        XCTAssertEqual(endpoint.console.path,"/cgi-bin/luci/admin/ddk/overview")
        XCTAssertEqual(endpoint.console.query,"orbit=1")
    }
    func testRejectsCredentialLeaksAndInsecureAddresses() {
        for input in ["http://192.168.8.1","https://root:password@192.168.8.1","https://192.168.8.1?password=test","https://192.168.8.1/#test","https://192.168.8.1/ddk","javascript:alert(1)","https://router.local:0"] {
            XCTAssertThrowsError(try RouterEndpoint(input),input)
        }
    }
    func testRedirectsRemainOnExactOrigin() throws {
        let endpoint = try RouterEndpoint("https://192.168.8.1")
        XCTAssertTrue(endpoint.contains(URL(string:"https://192.168.8.1/cgi-bin/luci/")))
        XCTAssertFalse(endpoint.contains(URL(string:"http://192.168.8.1/")))
        XCTAssertFalse(endpoint.contains(URL(string:"https://192.168.8.1.attacker.invalid/")))
        XCTAssertFalse(endpoint.contains(URL(string:"https://192.168.8.1:8443/")))
        XCTAssertFalse(endpoint.contains(URL(string:"https://root:secret@192.168.8.1/")))
    }
    func testFormEncodingPreservesLiteralCharacters() {
        let data = RouterEndpoint.form([("luci_username","test+operator"),("luci_password","a&b=+ ü")])
        XCTAssertEqual(String(data:data,encoding:.utf8),"luci_username=test%2Boperator&luci_password=a%26b%3D%2B%20%C3%BC")
    }
    func testIPv6AndCustomPort() throws {
        let endpoint = try RouterEndpoint("https://[fd00::1]:8443")
        XCTAssertTrue(endpoint.contains(URL(string:"https://[fd00::1]:8443/cgi-bin/luci/")))
        XCTAssertFalse(endpoint.contains(URL(string:"https://[fd00::1]/")))
    }
}
