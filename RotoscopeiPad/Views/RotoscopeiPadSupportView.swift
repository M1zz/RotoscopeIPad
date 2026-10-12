import SwiftUI
import LeeoKit

struct RotoscopeiPadSupportView: View {
    @EnvironmentObject private var store: LeeoStore
    @State private var showUnlock = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.hasPro {
                        Label("모든 기능이 열려 있어요", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button { showUnlock = true } label: {
                            Label("평생 이용권", systemImage: "star.fill")
                        }
                    }
                } header: { Text("이용권") }
                Section { LeeoSupportSection<RotoscopeiPadSpec>() } header: { Text("지원") }
            }
            .navigationTitle("설정")
            .sheet(isPresented: $showUnlock) {
                UnlockSheet(reason: .general)
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
