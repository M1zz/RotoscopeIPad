import SwiftUI
import LeeoKit

struct RotoscopeiPadSupportView: View {
    @EnvironmentObject private var store: LeeoStore
    @State private var showUnlock = false
    /// Kids can reach the gear, so feedback, reviews and web links wait
    /// behind the same grown-up check as the purchase screen.
    @State private var parentVerified = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if parentVerified {
            settings
        } else {
            ParentGateView(icon: "gearshape.fill") {
                withAnimation { parentVerified = true }
            }
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 34))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .padding(20)
                }
            }
        }
    }

    private var settings: some View {
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
            // "Enjoying Palang Book?" asks for a store review, so it's only
            // ever put to the grown-up who just passed the check.
            .leeoSatisfactionCheck(RotoscopeiPadSpec.self)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
