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
                .accessibilityLabel(Text("닫기"))
            }
        }
    }

    /// Opens the parent's own mail app, addressed to the developer, with the
    /// app name and version in the subject so the reply can find the build.
    private static var mailURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let subject = "\(RotoscopeiPadSpec.displayName) \(version)"
        let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(RotoscopeiPadSpec.developerEmail)?subject=\(encoded)")
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
                Section {
                    LeeoSupportSection<RotoscopeiPadSpec>()
                    if let mail = Self.mailURL {
                        Link(destination: mail) {
                            Label("메일로 문의하기", systemImage: "envelope")
                        }
                    }
                    // Only the handle is a proper noun; the label is translated.
                    Link(destination: URL(string: "https://instagram.com/lee25_ios")!) {
                        Label("인스타그램 DM (@lee25_ios)", systemImage: "paperplane")
                    }
                } header: { Text("지원") }
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
