import SwiftUI
import LeeoKit

@main
struct RotoscopeiPadApp: App {
    @StateObject private var project = RotoProject()

    init() {
        LeeoEngagement.shared.registerLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(project)
                .leeoSatisfactionCheck(RotoscopeiPadSpec.self)
        }
    }
}
