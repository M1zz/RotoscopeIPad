import Foundation
import LeeoKit

enum RotoscopeiPadSpec: LeeoAppSpec {
    static let appName = "팔랑북"
    static let developerEmail = "mizzking75@gmail.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub", appIdentifier: "com.leeo.RotoscopeiPad")

    /// 개인정보 처리방침·지원 페이지 (README 에 공개된 링크, docs/ 를 GitHub Pages 로 서빙).
    static let legal = LeeoLegalConfig(
        privacyURL: URL(string: "https://m1zz.github.io/RotoscopeIPad/privacy.html")!,
        supportURL: URL(string: "https://m1zz.github.io/RotoscopeIPad/")!
    )

    /// 부분유료 — 무료로 충분히 맛보고, 평생 이용권 한 번으로 전부 연다.
    /// 무료 한도는 여기 한 곳에만 있다 (키 이름은 FreeTier).
    static let monetization = LeeoMonetization.freemium(
        LeeoPurchaseConfig(
            productIDs: [FreeTier.lifetimeProductID],
            gate: LeeoGatePolicy(
                freeLimits: [
                    FreeTier.projectKey: 3,
                    FreeTier.blankPageKey: 10,
                    FreeTier.videoImportKey: 1,
                    FreeTier.recordSecondsKey: 15
                ],
                proOnly: [FreeTier.premiumPresetKey])))
}
