import Darwin
import Foundation
import XCTest
@testable import Binky

final class WhereFromsTests: XCTestCase {

    func testDomainMatchesExactAndWWW() {
        XCTAssertTrue(WhereFromsReader.domainMatches(pattern: "figma.com", host: "figma.com"))
        XCTAssertTrue(WhereFromsReader.domainMatches(pattern: "figma.com", host: "www.figma.com"))
        XCTAssertFalse(WhereFromsReader.domainMatches(pattern: "figma.com", host: "evilfigma.com"))
    }

    func testDomainMatchesWildcard() {
        XCTAssertTrue(WhereFromsReader.domainMatches(pattern: "*.stripe.com", host: "api.stripe.com"))
        XCTAssertTrue(WhereFromsReader.domainMatches(pattern: "*.stripe.com", host: "stripe.com"))
        XCTAssertFalse(WhereFromsReader.domainMatches(pattern: "*.stripe.com", host: "notstripe.com"))
    }

    func testMatchesAnyOriginPatternEmptyMeansMatch() {
        XCTAssertTrue(WhereFromsReader.matchesAnyOriginPattern([], hosts: ["a.com"]))
    }

    func testMatchesAnyOriginPatternRequiresHost() {
        XCTAssertTrue(WhereFromsReader.matchesAnyOriginPattern(["figma.com"], hosts: ["figma.com", "other.com"]))
        XCTAssertFalse(WhereFromsReader.matchesAnyOriginPattern(["figma.com"], hosts: ["other.com"]))
    }

    func testSanitizedOriginLabelStripsWeirdCharacters() {
        XCTAssertEqual(WhereFromsReader.sanitizedOriginLabel(forHost: "foo_bar.com"), "foo-bar.com")
    }

    func testOriginHostsFromXattrPlistArray() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("binky-wherefroms-\(UUID().uuidString)")
        try Data().write(to: tmp)

        let plistStrings = [
            "https://www.figma.com/file/abc",
            "https://dl.figma.com/asset.png",
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plistStrings,
            format: .binary,
            options: 0
        )

        let written = plistData.withUnsafeBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return -1 }
            return setxattr(tmp.path, WhereFromsReader.xattrName, base, plistData.count, 0, 0)
        }
        XCTAssertEqual(written, 0)

        let hosts = WhereFromsReader.originHosts(forFileAt: tmp)
        XCTAssertEqual(hosts, ["figma.com", "dl.figma.com"])

        try FileManager.default.removeItem(at: tmp)
    }

    func testSourceURLsMissingXattrIsEmpty() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("binky-no-xattr-\(UUID().uuidString)")
        try? Data().write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertTrue(WhereFromsReader.sourceURLs(forFileAt: tmp).isEmpty)
        XCTAssertNil(WhereFromsReader.primaryOriginHost(forFileAt: tmp))
    }

    func testMalformedPlistYieldsNoURLs() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("binky-bad-plist-\(UUID().uuidString)")
        try "not a plist".data(using: .utf8)!.write(to: tmp)

        let written = "x".data(using: .utf8)!.withUnsafeBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return -1 }
            return setxattr(tmp.path, WhereFromsReader.xattrName, base, 1, 0, 0)
        }
        XCTAssertEqual(written, 0)

        XCTAssertTrue(WhereFromsReader.sourceURLs(forFileAt: tmp).isEmpty)
        try FileManager.default.removeItem(at: tmp)
    }
}
