import XCTest
import CoreGraphics
@testable import RotoscopeiPad

/// Saved projects and the shapes kids stamp — the parts a regression would
/// silently break (old works failing to open, stamps drawn off the page).
@MainActor
final class DrawingModelTests: XCTestCase {

    // MARK: - MaskStroke / FrameMask persistence

    func testStrokeSavedBeforePaintAttributesStillLoads() throws {
        // project.json from the first builds: only points were written.
        let json = #"{"points":[[0.1,0.2],[0.3,0.4]]}"#.data(using: .utf8)!
        let stroke = try JSONDecoder().decode(MaskStroke.self, from: json)
        XCTAssertEqual(stroke.points, [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.4)])
        XCTAssertTrue(stroke.isAdditive)
        XCTAssertTrue(stroke.closed)
        XCTAssertEqual(stroke.colorHex, "FF3B30")
        XCTAssertEqual(stroke.width, 0.012, accuracy: 1e-9)
        XCTAssertEqual(stroke.opacity, 1.0, accuracy: 1e-9)
        XCTAssertTrue(stroke.smooth)
    }

    func testStrokeRoundTripsThroughJSON() throws {
        let stroke = MaskStroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0.5)],
                                isAdditive: false, closed: false, colorHex: "007AFF",
                                width: 0.034, opacity: 0.5, smooth: false)
        let data = try JSONEncoder().encode(FrameMask(strokes: [stroke]))
        let back = try JSONDecoder().decode(FrameMask.self, from: data)
        XCTAssertEqual(back.strokes, [stroke])
    }

    func testFrameMaskIsEmptyOnlyWithoutPoints() {
        XCTAssertTrue(FrameMask().isEmpty)
        XCTAssertTrue(FrameMask(strokes: [MaskStroke(points: [])]).isEmpty)
        XCTAssertFalse(FrameMask(strokes: [MaskStroke(points: [CGPoint(x: 0.5, y: 0.5)])]).isEmpty)
    }

    // MARK: - Stamps

    func testEveryStampIsAClosedShapeInsideTheUnitBox() {
        for shape in StampShape.allCases {
            let points = shape.unitPoints
            XCTAssertGreaterThanOrEqual(points.count, 3, "\(shape) needs an area to fill")
            for p in points {
                XCTAssertTrue((-1.0001...1.0001).contains(p.x) && (-1.0001...1.0001).contains(p.y),
                              "\(shape) point \(p) leaves the unit box")
            }
            let path = StrokeGeometry.path(points: points, closed: true, smooth: shape.smooth)
            XCTAssertFalse(path.boundingBoxOfPath.isEmpty, "\(shape) draws nothing")
        }
    }

    func testStampIdentifiersAreUnique() {
        let ids = StampShape.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - Stroke geometry

    func testFewerThanTwoPointsDrawNothing() {
        XCTAssertTrue(StrokeGeometry.path(points: [], closed: false, smooth: true).isEmpty)
        XCTAssertTrue(StrokeGeometry.path(points: [CGPoint(x: 1, y: 1)],
                                          closed: false, smooth: true).isEmpty)
    }

    func testStraightStrokeCoversExactlyItsPoints() {
        let path = StrokeGeometry.path(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
                                                CGPoint(x: 10, y: 5)],
                                       closed: false, smooth: false)
        XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 10, height: 5))
        XCTAssertEqual(path.currentPoint, CGPoint(x: 10, y: 5))
    }

    func testSmoothOpenStrokeEndsOnTheLastPoint() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 3), CGPoint(x: 8, y: 0),
                      CGPoint(x: 12, y: 3)]
        let path = StrokeGeometry.path(points: points, closed: false, smooth: true)
        XCTAssertEqual(path.currentPoint, points.last)
        // Endpoints clamp to their neighbour, so the curve stays near the line.
        let box = path.boundingBoxOfPath
        XCTAssertGreaterThanOrEqual(box.minX, -0.5)
        XCTAssertLessThanOrEqual(box.maxX, 12.5)
    }
}
