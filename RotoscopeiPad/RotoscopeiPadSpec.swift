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

    /// 결제 없음 — 앱 안에 StoreKit·페이월 코드가 존재하지 않는다.
    static let monetization = LeeoMonetization.free
}
