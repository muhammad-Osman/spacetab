import XCTest
@testable import SpaceTab

final class GridLayoutTests: XCTestCase {
    private func thumbnails(_ count: Int, in size: CGSize) -> GridLayout {
        GridLayout.fitting(
            count: count, in: size, spacing: 10, aspectRatio: 0.625, extraHeight: 26,
            minCellWidth: 140, maxCellWidth: 320
        )
    }

    func testFewWindowsGoInOneRowAtFullSize() {
        let layout = thumbnails(4, in: CGSize(width: 1600, height: 800))
        XCTAssertEqual(layout.columns, 4)
        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(layout.cellSize.width, 320)
    }

    func testManyWindowsShrinkToFitWithoutScrolling() {
        let available = CGSize(width: 1400, height: 800)
        let layout = thumbnails(20, in: available)
        XCTAssertLessThan(layout.cellSize.width, 320)
        XCTAssertGreaterThanOrEqual(layout.cellSize.width, 140)
        XCTAssertLessThanOrEqual(layout.contentSize.width, available.width)
        XCTAssertLessThanOrEqual(layout.contentSize.height, available.height)
    }

    func testTooManyWindowsKeepMinimumSizeAndScroll() {
        let available = CGSize(width: 800, height: 400)
        let layout = thumbnails(100, in: available)
        XCTAssertEqual(layout.cellSize.width, 140)
        XCTAssertLessThanOrEqual(layout.contentSize.width, available.width)
        XCTAssertGreaterThan(layout.contentSize.height, available.height)
    }

    func testFixedCellsWrapToAvailableWidth() {
        let layout = GridLayout.fixed(count: 10, cellSize: CGSize(width: 96, height: 96), spacing: 4, availableWidth: 500)
        XCTAssertEqual(layout.columns, 5)
        XCTAssertEqual(layout.rows, 2)
    }

    func testPartialLastRowIsCentered() {
        let layout = GridLayout.fixed(count: 3, cellSize: CGSize(width: 100, height: 100), spacing: 0, availableWidth: 200)
        XCTAssertEqual(layout.frame(ofCell: 0).minX, 0)
        XCTAssertEqual(layout.frame(ofCell: 1).minX, 100)
        XCTAssertEqual(layout.frame(ofCell: 2), CGRect(x: 50, y: 100, width: 100, height: 100))
    }
}
