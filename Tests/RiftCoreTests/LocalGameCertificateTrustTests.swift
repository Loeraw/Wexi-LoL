import XCTest
import Security
@testable import RiftCore

final class LocalGameCertificateTrustTests: XCTestCase {
    private func certificate(_ name: String) throws -> SecCertificate {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "der", subdirectory: "Fixtures"))
        return try XCTUnwrap(SecCertificateCreateWithData(nil, Data(contentsOf: url) as CFData))
    }

    private func verify(_ leaf: String = "valid", anchor: String = "anchor", year: Int = 2030) throws -> Bool {
        var trust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates(try certificate(leaf),
            SecPolicyCreateSSL(true, "127.0.0.1" as CFString), &trust), errSecSuccess)
        let value = try XCTUnwrap(trust)
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 6, day: 1)))
        SecTrustSetVerifyDate(value, date as CFDate)
        return LocalGameCertificateTrust.evaluate(value, anchor: try certificate(anchor))
    }

    func testLongLivedPinnedLocalCertificate() throws { XCTAssertTrue(try verify()) }
    func testRejectsUnrelatedIssuer() throws { XCTAssertFalse(try verify(anchor: "unrelated")) }
    func testRejectsWrongIPAddress() throws { XCTAssertFalse(try verify("wrong-ip")) }
    func testRejectsClientOnlyCertificate() throws { XCTAssertFalse(try verify("wrong-purpose")) }
    func testRejectsExpiredCertificate() throws { XCTAssertFalse(try verify(year: 2200)) }
    func testRejectsNotYetValidCertificate() throws { XCTAssertFalse(try verify(year: 2020)) }
}
