import SwiftUI

@main
struct RotoscopeiPadApp: App {
    @StateObject private var project = RotoProject()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(project)
        }
    }
}
