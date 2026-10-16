import XCTest
import SwiftUI
import LeeoKit
@testable import RotoscopeiPad

/// Colors, brush sizes and the free-tier rules — what a parent sees on the
/// screen and on the bill.
@MainActor
final class PaletteAndFreeTierTests: XCTestCase {

    // MARK: - Hex colors

    func testHexParsesIntoRGBComponents() {
        let c = "FF9500".rgbComponents
        XCTAssertEqual(c.r, 1, accuracy: 1e-6)
        XCTAssertEqual(c.g, CGFloat(0x95) / 255, accuracy: 1e-6)
        XCTAssertEqual(c.b, 0, accuracy: 1e-6)

        let hash = "#007AFF".rgbComponents
        XCTAssertEqual(hash.r, 0, accuracy: 1e-6)
        XCTAssertEqual(hash.g, CGFloat(0x7A) / 255, accuracy: 1e-6)
        XCTAssertEqual(hash.b, 1, accuracy: 1e-6)
    }

    func testEveryPaletteColorRoundTripsThroughColor() {
        for hex in RotoProject.palette {
            XCTAssertEqual(Color(rgbHex: hex).hexString, hex)
        }
    }

    func testPaletteHasNoDuplicates() {
        XCTAssertEqual(Set(RotoProject.palette).count, RotoProject.palette.count)
    }

    /// The VoiceOver names read the sizes by position (thin → thick, small → big).
    func testSizePresetsAreOrderedSmallestFirst() {
        let widths = RotoProject.widthPresets.map(\.value)
        XCTAssertEqual(widths, widths.sorted())
        XCTAssertEqual(Set(widths).count, widths.count)
        XCTAssertEqual(RotoProject.stampSizePresets, RotoProject.stampSizePresets.sorted())
    }

    // MARK: - Free tier

    private var freeGate: LeeoGate {
        LeeoGate(policy: RotoscopeiPadSpec.gate, hasPro: false, isTrialActive: false)
    }

    func testFreeInstallKeepsThreeWorks() {
        XCTAssertTrue(freeGate.evaluate(FreeTier.projectKey, current: 2).isAllowed)
        XCTAssertFalse(freeGate.evaluate(FreeTier.projectKey, current: 3).isAllowed)
    }

    func testFreeBlankFlipbookStopsAtTenPages() {
        XCTAssertTrue(freeGate.evaluate(FreeTier.blankPageKey, current: 9).isAllowed)
        XCTAssertFalse(freeGate.evaluate(FreeTier.blankPageKey, current: 10).isAllowed)
    }

    func testOnlyOneFreeVideoImport() {
        XCTAssertTrue(freeGate.evaluate(FreeTier.videoImportKey, current: 0).isAllowed)
        XCTAssertFalse(freeGate.evaluate(FreeTier.videoImportKey, current: 1).isAllowed)
    }

    func testPremiumGuideSetsNeedThePass() {
        XCTAssertFalse(freeGate.allows(FreeTier.premiumPresetKey))
        let paid = LeeoGate(policy: RotoscopeiPadSpec.gate, hasPro: true, isTrialActive: false)
        XCTAssertTrue(paid.allows(FreeTier.premiumPresetKey))
        XCTAssertTrue(paid.evaluate(FreeTier.projectKey, current: 500).isAllowed)
    }

    func testRecordingLimitOnlyForFreeInstalls() {
        XCTAssertEqual(FreeTier.recordingLimit(hasPro: false), 15)
        XCTAssertNil(FreeTier.recordingLimit(hasPro: true))
    }

    func testFreeGuideSetsAreBundled() {
        let bundled = Set(PresetLibrary.all.map(\.id))
        XCTAssertFalse(bundled.isEmpty)
        XCTAssertTrue(FreeTier.freePresetIDs.isSubset(of: bundled),
                      "a free guide set is missing from Presets/")
        for preset in PresetLibrary.all {
            XCTAssertEqual(FreeTier.isFree(preset), FreeTier.freePresetIDs.contains(preset.id))
            XCTAssertFalse(preset.frameURLs.isEmpty, "\(preset.id) has no pages")
        }
    }

    func testEveryLockReasonHasAPictureAndAMessage() {
        for reason in [LockReason.projects, .presets, .video, .pages, .recording, .general] {
            XCTAssertFalse(reason.icon.isEmpty)
            XCTAssertFalse(reason.message.isEmpty)
        }
    }
}
