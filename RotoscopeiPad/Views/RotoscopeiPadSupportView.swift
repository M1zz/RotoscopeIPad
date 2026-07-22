import SwiftUI
import LeeoKit

struct RotoscopeiPadSupportView: View {
    var body: some View {
        NavigationStack {
            List {
                Section { LeeoSupportSection<RotoscopeiPadSpec>() } header: { Text("지원") }
            }
            .navigationTitle("설정")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
