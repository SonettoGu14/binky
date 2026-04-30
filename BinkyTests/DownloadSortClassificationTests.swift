import XCTest
@testable import Binky

final class DownloadSortClassificationTests: XCTestCase {

    func testPdfRoutesToPdfBucket() {
        let url = URL(fileURLWithPath: "/tmp/invoice.pdf")
        XCTAssertEqual(FileClassification.categorize(url: url), .pdf)
    }

    func testScreenshotNamedPdfRoutesToScreenshots() {
        let url = URL(fileURLWithPath: "/tmp/Screenshot 2025-04-29 at 12.00.00.pdf")
        XCTAssertEqual(FileClassification.categorize(url: url), .screenshots)
    }

    func testUnknownExtensionRoutesToReview() {
        let url = URL(fileURLWithPath: "/tmp/weird.xyzabc")
        XCTAssertEqual(FileClassification.categorize(url: url), .review)
    }

    func testEmptyExtensionRoutesToReview() {
        let url = URL(fileURLWithPath: "/tmp/README")
        XCTAssertEqual(FileClassification.categorize(url: url), .review)
    }

    func testArchiveRoutesToArchives() {
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/a/z.zip")), .archives)
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/a/z.tar.gz")), .archives)
    }

    func testInstallerRoutesToApps() {
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/a/Binky.dmg")), .apps)
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/a/Thing.pkg")), .apps)
    }

    func testTransientSuffixRoutesToReview() {
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/dl/big.iso.crdownload")), .review)
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/dl/foo.part")), .review)
    }

    func testDotfileRoutesToReview() {
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/tmp/.DS_Store")), .review)
    }

    func testJpegRoutesToImagesWhenNotScreenshotNamed() {
        let url = URL(fileURLWithPath: "/tmp/photo.jpeg")
        XCTAssertEqual(FileClassification.categorize(url: url), .images)
    }

    func testMp4RoutesToVideo() {
        let url = URL(fileURLWithPath: "/tmp/clip.mp4")
        XCTAssertEqual(FileClassification.categorize(url: url), .video)
    }
}
