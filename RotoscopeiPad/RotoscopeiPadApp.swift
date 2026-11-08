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
                .environmentObject(project)
                .environmentObject(store)
                // Re-read the pass when it changes (purchase, offer code) and on every return.
                .task(id: store.hasPro) { await syncLatch() }
                .onChange(of: scenePhase, onReturn)
        }
    }

    private func onReturn(_: ScenePhase, to phase: ScenePhase) {
        if phase == .active { Task { await syncLatch() } }
    }

    private func syncLatch() async {
        if await ProLatch.sync() { store.objectWillChange.send() }
    }
}
