import SwiftUI
import LeeoKit
import TipKit

@main
struct RotoscopeiPadApp: App {
    @StateObject private var project = RotoProject()
    @StateObject private var store: LeeoStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 실행 기록·크래시 진단·익명 사용 통계·원격 킬스위치를 한 번에 켠다 (registerLaunch 포함).
        LeeoKit.bootstrap(RotoscopeiPadSpec.self, flags: PalangFlag.self)
        // Before anything is created: works already on disk mean this iPad
        // used 팔랑북 while it was free, and keeps everything.
        FreeTier.markLegacyUserIfNeeded()
        // Flipbooks stay open where kids were already making them.
        Flipbooks.openForExistingUsers()
        // Editor hints (PalangTips.swift); each one shows at most once.
        try? Tips.configure([.displayFrequency(.immediate)])
        _store = StateObject(wrappedValue: LeeoStore(
            config: RotoscopeiPadSpec.paywall!,
            // A family that once had the lifetime pass keeps it until a refund (ProLatch).
            unlockOverride: { ProLatch.isLatched ? true : nil },
            grandfather: { await FreeTier.isLegacyUser() }))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 개발자가 보낸 의견에 답장하면, 앱이 앞으로 올 때 답장을 시트로 보여 준다 (LeeoKit).
                .leeoFeedbackReplyNotice(RotoscopeiPadSpec.self)
                .environmentObject(project)
                .environmentObject(store)
                // Re-read the pass when it changes (purchase, offer code) and on every return.
                .task(id: store.hasPro) { await syncLatch() }
                .onChange(of: scenePhase, onReturn)
                .environment(\.locale, .app)
        }
    }

    private func onReturn(_: ScenePhase, to phase: ScenePhase) {
        if phase == .active { Task { await syncLatch() } }
    }

    private func syncLatch() async {
        if await ProLatch.sync() { store.objectWillChange.send() }
    }
}

extension Locale {
    /// The locale numbers and dates are written in. Arabic keeps 0-9 and the
    /// Gregorian calendar so counts, page numbers and dates never mix digit
    /// sets; every other language follows the device as before.
    static var app: Locale {
        guard Bundle.main.preferredLocalizations.first == "ar" else { return .current }
        var parts = Locale.Components(locale: .current)
        parts.numberingSystem = "latn"
        parts.calendar = .gregorian
        return Locale(components: parts)
    }
}

/// An LTR run (page numbers, "7 × 8 =") that keeps its order inside RTL text.
func ltrIsolated(_ text: String) -> String { "\u{2066}\(text)\u{2069}" }
