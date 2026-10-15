import Foundation
import LeeoKit

enum RotoscopeiPadSpec: LeeoAppSpec {
    static let appName = "팔랑북"
    static let developerEmail = "mizzking75@gmail.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub", appIdentifier: "com.leeo.RotoscopeiPad")

    /// 개인정보 처리방침·지원 페이지 (README 에 공개된 링크, docs/ 를 GitHub Pages 로 서빙).
    /// 앱이 보이는 언어의 페이지로 연다 — 한국어는 최상단, 나머지는 docs/<언어>/.
    /// 이용약관은 Apple 표준 EULA (App Store Connect 에 따로 약관을 올리지 않았으므로).
    static let legal = LeeoLegalConfig(
        privacyURL: URL(string: "\(webRoot)privacy.html")!,
        supportURL: URL(string: webRoot == baseURL ? baseURL : "\(webRoot)support.html")!,
        termsURL: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    )

    private static let baseURL = "https://m1zz.github.io/RotoscopeIPad/"

    /// Languages with their own folder under docs/ (ko lives at the root).
    private static let webLanguages: Set<String> = [
        "en", "ja", "zh-Hans", "zh-Hant", "es", "de", "fr", "pt-BR", "it"
    ]

    /// The docs/ folder for the language the app is showing right now.
    private static let webRoot: String = {
        guard let lang = Bundle.main.preferredLocalizations.first,
              webLanguages.contains(lang) else { return baseURL }
        return "\(baseURL)\(lang)/"
    }()

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
