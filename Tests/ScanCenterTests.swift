import XCTest
import PDFKit
import UIKit
@testable import ScanCenter

final class ScanCenterTests: XCTestCase {
    func testTrustedAddressAndFileNames() throws {
        for host in ["192.168.31.47", "10.0.0.2", "172.31.9.2"] {
            let address = try ServerAddress(host: host, port: 8088)
            XCTAssertEqual(try address.url("/api/session").host, host)
            XCTAssertThrowsError(try address.url("/api/../secret"))
            XCTAssertThrowsError(try address.url("/api/session?url=https://example.com"))
        }
        for host in ["127.0.0.1", "8.8.8.8", "169.254.1.1", "192.168.01.47", "192.168.31.47.evil", "172.32.1.1"] {
            XCTAssertThrowsError(try ServerAddress(host: host, port: 8088))
        }
    }

    @MainActor func testPageIDsAndDPI() throws {
        XCTAssertTrue(HiNASClient.validPage("page-10.png"))
        XCTAssertFalse(HiNASClient.validPage("page-11.png"))
        XCTAssertFalse(HiNASClient.validPage("../original.png"))
        let reply = Data("""
        {"ok":true,"options":{"resolution":{"values":[100,200,300,600,1200]},"source":{"values":["FlatBed","Automatic Document Feeder"]}},"scan_center_api":{"adf_batch":true,"adf_max_dpi":600,"adf_page_limit":10}}
        """.utf8)
        let caps = try JSONDecoder().decode(ScanCapabilities.self, from: reply)
        XCTAssertTrue(caps.supportsFeeder)
        XCTAssertEqual(caps.resolutions(for: .feeder), [100, 200, 300, 600])
        let encoded = try JSONEncoder().encode(ScanOptions())
        let options = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(options["source"] as? String, "Automatic Document Feeder")
        XCTAssertEqual(options["dpi"] as? Int, 600)
    }

    func testLosslessPDFPageSizeAndRotation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Use a genuine device-style RGB PNG with a tiny known fixture.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAGUlEQVR4nB3BgQkAAAzDIOn/P2cwhWoV5h1T6wX/eeBbbwAAAABJRU5ErkJggg==")!
        let file = root.appendingPathComponent("page.png")
        try png.write(to: file)
        let info = try PNGInfo.read(file)
        XCTAssertEqual(info.width, 2)
        let page = DocumentPage(id: UUID(), file: "page.png", dpi: 600, width: 2, height: 3)
        var rotated = page; rotated.rotation = 90
        let output = root.appendingPathComponent("pages.pdf")
        try LosslessPDF.write(pages: [(file, page), (file, rotated)], to: output)
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(document.page(at: 0)!.bounds(for: .mediaBox).width, 0.24, accuracy: 0.001)
    }
}
