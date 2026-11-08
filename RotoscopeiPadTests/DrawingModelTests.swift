import XCTest
import CoreGraphics
import UIKit
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

    func testEveryStampIsMadeOfClosedPiecesInsideTheUnitBox() {
        for shape in StampShape.allCases {
            XCTAssertFalse(shape.parts.isEmpty, "\(shape) has no pieces")
            for part in shape.parts {
                XCTAssertGreaterThanOrEqual(part.points.count, 3, "\(shape) needs an area to fill")
                for p in part.points {
                    XCTAssertTrue((-1.0001...1.0001).contains(p.x) && (-1.0001...1.0001).contains(p.y),
                                  "\(shape) point \(p) leaves the unit box")
                }
                let path = StrokeGeometry.path(points: part.points, closed: true, smooth: part.smooth)
                XCTAssertFalse(path.boundingBoxOfPath.isEmpty, "\(shape) draws nothing")
            }
        }
    }

    func testStampIdentifiersAreUnique() {
        let ids = StampShape.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testToolbarNeverShowsMoreThanTenStamps() {
        let all = StampShape.allCases.map(\.rawValue).joined(separator: ",")
        XCTAssertEqual(StampShape.chosen(all).count, StampShape.limit)
        XCTAssertLessThanOrEqual(StampShape.chosen(StampShape.starterIDs).count, StampShape.limit)
        XCTAssertTrue(StampShape.chosen("").isEmpty)
        XCTAssertEqual(StampShape.chosen("cat,gone,heart"), [.heart, .cat])
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

    // MARK: - Trash: nothing a kid throws away is gone for good

    func testWipedPageWaitsInTrashAndComesBack() throws {
        let before = Set(RotoProject.listTrash())
        let project = RotoProject()
        project.createBlank()
        let work = try XCTUnwrap(project.projectDirectory)
        project.commitStroke(MaskStroke(points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9)]))
        project.clearCurrentMask()
        XCTAssertTrue(project.currentMask.isEmpty)

        // The wiped drawing is a one-page work of its own in the trash.
        let trashed = Set(RotoProject.listTrash()).subtracting(before)
        let page = try XCTUnwrap(trashed.first)
        XCTAssertEqual(trashed.count, 1)

        // Brought back, it opens on the shelf with the drawing.
        RotoProject.restoreFromTrash([page])
        let restored = RotoProject.projectsRoot.appendingPathComponent(page.lastPathComponent)
        XCTAssertTrue(RotoProject.listProjects().contains(restored))
        project.openProject(at: restored)
        XCTAssertEqual(project.currentMask.strokes.count, 1)
        XCTAssertTrue(project.isSketchbook)

        // Shelf → trash → gone for good.
        project.goHome()
        RotoProject.moveToTrash([restored, work])
        XCTAssertFalse(RotoProject.listProjects().contains(restored))
        RotoProject.deleteFromTrash(Set(RotoProject.listTrash()).subtracting(before))
        XCTAssertEqual(Set(RotoProject.listTrash()), before)
    }

    func testHandMovesAWholeStampButNotLines() throws {
        let project = RotoProject()
        project.createBlank()
        let work = try XCTUnwrap(project.projectDirectory)
        defer { project.goHome(); RotoProject.moveToTrash([work]) }
        let line = MaskStroke(points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.9)], closed: false)
        project.commitStroke(line)
        project.stampShape = .cat
        project.stamp(at: CGPoint(x: 0.5, y: 0.5))
        let before = project.currentMask.strokes

        // Grabbing the line does nothing; grabbing the cat moves every piece.
        project.grabShape(at: CGPoint(x: 0.15, y: 0.5))
        project.dragShape(to: CGPoint(x: 0.3, y: 0.5))
        project.dropShape()
        XCTAssertEqual(project.currentMask.strokes, before)

        project.grabShape(at: CGPoint(x: 0.5, y: 0.52))
        project.dragShape(to: CGPoint(x: 0.6, y: 0.52))
        project.dropShape()
        let after = project.currentMask.strokes
        XCTAssertEqual(after[0], line)
        for (old, new) in zip(before.dropFirst(), after.dropFirst()) {
            XCTAssertEqual(new.points[0].x - old.points[0].x, 0.1, accuracy: 0.0001)
            XCTAssertEqual(new.points[0].y, old.points[0].y, accuracy: 0.0001)
        }
    }

    func testSketchbookOverAPictureKeepsItsPicture() throws {
        let size = CGSize(width: 300, height: 600)
        let png = try XCTUnwrap(UIGraphicsImageRenderer(size: size).image { _ in }.pngData())
        let pictures = Set(PictureLibrary.list())
        PictureLibrary.add(png)
        let added = try XCTUnwrap(Set(PictureLibrary.list()).subtracting(pictures).first)
        defer { PictureLibrary.remove(added) }

        let project = RotoProject()
        project.createFromPicture(added, faded: true)
        let work = try XCTUnwrap(project.projectDirectory)
        defer { RotoProject.moveToTrash([work]) }
        XCTAssertEqual(project.canvasSize.width / project.canvasSize.height, 0.5, accuracy: 0.01)
        project.fitPage(to: CGSize(width: 1000, height: 700))   // the picture keeps its shape
        XCTAssertEqual(project.canvasSize.width / project.canvasSize.height, 0.5, accuracy: 0.01)

        project.goHome()
        XCTAssertNil(project.picture)
        project.openProject(at: work)
        XCTAssertNotNil(project.picture)
        XCTAssertTrue(project.pictureFaded)
        project.goHome()
    }
}
