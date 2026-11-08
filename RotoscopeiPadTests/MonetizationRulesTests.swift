import XCTest
import LeeoKit
@testable import RotoscopeiPad

/// The money rules that must never quietly break: a bought pass stays,
/// a gift never unlocks its buyer, and free-era families keep everything.
final class MonetizationRulesTests: XCTestCase {

    // MARK: - Lifetime latch

    func testLatchRisesOnAnyLiveTransaction() {
        XCTAssertEqual(ProLatch.evidence(revocationDates: [nil]), .owned)
        XCTAssertEqual(ProLatch.evidence(revocationDates: [Date(), nil]), .owned)
        XCTAssertTrue(ProLatch.decide(latched: false, evidence: .owned))
    }

    /// Offline, a new iCloud sign-in, Family Sharing still syncing: no news is not a refund.
    func testSilenceNeverLowersTheLatch() {
        XCTAssertEqual(ProLatch.evidence(revocationDates: []), .unknown)
        XCTAssertTrue(ProLatch.decide(latched: true, evidence: .unknown))
        XCTAssertFalse(ProLatch.decide(latched: false, evidence: .unknown))
    }

    func testOnlyARefundLowersTheLatch() {
        XCTAssertEqual(ProLatch.evidence(revocationDates: [Date()]), .refunded)
        XCTAssertFalse(ProLatch.decide(latched: true, evidence: .refunded))
    }

    // MARK: - Gifts and tips never sell Pro

    func testGiftAndTipsStayOutOfWhatUnlocksPro() throws {
        let config = try XCTUnwrap(RotoscopeiPadSpec.paywall)
        let unlocking = Set(config.productIDs).union(config.entitlementIDs)
        let notForSale = Set(FreeTier.tipProductIDs + [FreeTier.giftProductID])
        XCTAssertTrue(unlocking.isDisjoint(with: notForSale), "\(unlocking.intersection(notForSale))")
    }

    func testGiftGrantsTheLifetimePassThroughOfferCodes() throws {
        let gift = try XCTUnwrap(RotoscopeiPadSpec.paywall?.gifts.first)
        XCTAssertEqual(gift.productID, FreeTier.giftProductID)
        XCTAssertEqual(gift.grantsProductID, FreeTier.lifetimeProductID)
        XCTAssertTrue(gift.sellsGifts)
        XCTAssertTrue(try XCTUnwrap(RotoscopeiPadSpec.paywall).entitlementIDs.contains(FreeTier.lifetimeProductID))
    }

    // MARK: - Free-era families keep everything

    func testFirstDownloadsWhileFreeKeepEverything() {
        XCTAssertTrue(FreeTier.isFreeEraBuild("1"))
        XCTAssertTrue(FreeTier.isFreeEraBuild("2"))
        XCTAssertFalse(FreeTier.isFreeEraBuild("3"))
        XCTAssertFalse(FreeTier.isFreeEraBuild("1.0"))   // sandbox / Xcode never counts
    }
}
