import XCTest
@testable import SpaceTab

final class PreviewLayoutTests: XCTestCase {
    func testLandscapeFitsWidth() {
        XCTAssertEqual(PreviewLayout.fittedSize(imageSize: CGSize(width: 800, height: 400), in: CGSize(width: 300, height: 300)), CGSize(width: 300, height: 150))
    }

    func testPortraitFitsHeight() {
        XCTAssertEqual(PreviewLayout.fittedSize(imageSize: CGSize(width: 400, height: 800), in: CGSize(width: 300, height: 300)), CGSize(width: 150, height: 300))
    }

    func testSmallImagesDoNotScalePastTwiceTheirSize() {
        XCTAssertEqual(PreviewLayout.fittedSize(imageSize: CGSize(width: 40, height: 20), in: CGSize(width: 800, height: 800)), CGSize(width: 80, height: 40))
    }

    func testZeroSizesReturnZero() {
        XCTAssertEqual(PreviewLayout.fittedSize(imageSize: .zero, in: CGSize(width: 100, height: 100)), .zero)
        XCTAssertEqual(PreviewLayout.fittedSize(imageSize: CGSize(width: 100, height: 100), in: .zero), .zero)
    }
}
