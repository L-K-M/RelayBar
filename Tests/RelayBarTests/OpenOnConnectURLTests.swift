import XCTest
@testable import RelayBar

final class OpenOnConnectURLTests: XCTestCase {
    func testAcceptsHTTPAndHTTPSURLs() {
        XCTAssertEqual(
            OpenOnConnectURL.validate("http://localhost:8080/").url,
            URL(string: "http://localhost:8080/")
        )
        XCTAssertEqual(
            OpenOnConnectURL.validate("  https://example.com/admin?tab=1  ").url,
            URL(string: "https://example.com/admin?tab=1")
        )
        XCTAssertEqual(
            OpenOnConnectURL.validate("http://[::1]:81/").url,
            URL(string: "http://[::1]:81/")
        )
    }

    func testBlankValueIsUnset() {
        XCTAssertEqual(OpenOnConnectURL.validate(""), .unset)
        XCTAssertEqual(OpenOnConnectURL.validate(" \n"), .unset)
    }

    func testRejectsSchemesThatCouldLaunchSomethingOtherThanABrowser() {
        for value in [
            "file:///Applications/Calculator.app",
            "ssh://example.com",
            "javascript:alert(1)",
            "localhost:8080",
        ] {
            XCTAssertNotNil(
                OpenOnConnectURL.validate(value).errorMessage,
                "\(value) must be rejected."
            )
        }
    }

    func testRejectsMissingHostAndEmbeddedSpaces() {
        XCTAssertNotNil(OpenOnConnectURL.validate("http:///admin").errorMessage)
        XCTAssertNotNil(OpenOnConnectURL.validate("http://").errorMessage)
        XCTAssertNotNil(OpenOnConnectURL.validate("http://a b/").errorMessage)
    }

    func testStoredValueMustBeTrimmedAndValid() {
        XCTAssertTrue(OpenOnConnectURL.isValidStoredValue(nil))
        XCTAssertTrue(OpenOnConnectURL.isValidStoredValue("http://localhost/"))
        XCTAssertFalse(OpenOnConnectURL.isValidStoredValue(" http://localhost/"))
        XCTAssertFalse(OpenOnConnectURL.isValidStoredValue(""))
        XCTAssertFalse(OpenOnConnectURL.isValidStoredValue("file:///tmp"))
    }

    func testUnsafeStoredURLMakesProfileUnsafeToRun() {
        var tunnel = Tunnel(
            name: "Web",
            localPort: 43_210,
            destinationHost: "127.0.0.1",
            destinationPort: 80,
            sshHost: "example.com"
        )
        XCTAssertTrue(tunnel.isSafeToRun)

        tunnel.openOnConnectURL = "http://localhost:43210/"
        XCTAssertTrue(tunnel.isSafeToRun)

        tunnel.openOnConnectURL = "file:///tmp"
        XCTAssertFalse(tunnel.isSafeToRun)
    }

    func testRoundTripsAndDecodesMissingKeyAsUnset() throws {
        var tunnel = Tunnel(
            name: "Web",
            localPort: 43_210,
            destinationHost: "127.0.0.1",
            destinationPort: 80,
            sshHost: "example.com"
        )
        let withoutURL = try JSONEncoder().encode(tunnel)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: withoutURL) as? [String: Any]
        )
        XCTAssertNil(object["openOnConnectURL"])
        XCTAssertNil(try JSONDecoder().decode(Tunnel.self, from: withoutURL).openOnConnectURL)

        tunnel.openOnConnectURL = "https://example.com/dashboard"
        let decoded = try JSONDecoder().decode(
            Tunnel.self,
            from: JSONEncoder().encode(tunnel)
        )
        XCTAssertEqual(decoded, tunnel)
    }
}
