import SwiftUI
import LeeoKit

@main
struct RotoscopeiPadApp: App {
    @StateObject private var project = RotoProject()
    @StateObject private var store: LeeoStore

    init() {
        LeeoEngagement.shared.registerLaunch()
        // Before anything is created: works already on disk mean this iPad
        // used 팔랑북 while it was free, and keeps everything.
        FreeTier.markLegacyUserIfNeeded()
        _store = StateObject(wrappedValue: LeeoStore(
            config: RotoscopeiPadSpec.paywall!,
            grandfather: { await FreeTier.isLegacyUser() }))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(project)
                .environmentObject(store)
                .leeoSatisfactionCheck(RotoscopeiPadSpec.self)
        }
    }
}
