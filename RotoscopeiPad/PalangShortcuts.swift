import AppIntents
import SwiftUI

/// Hands a request from an App Intent to the running UI. The intent opens
/// the app; ContentView picks the request up and does it with the same
/// free-tier checks as tapping the card on the home grid.
@MainActor
final class ShortcutRouter: ObservableObject {
    static let shared = ShortcutRouter()

    enum Request: Equatable {
        case newBlankFlipbook
    }

    @Published var pending: Request?
}

/// "Hey Siri, new flipbook in Palang Book" — opens straight onto a fresh
/// blank page, ready to draw.
struct NewBlankFlipbookIntent: AppIntent {
    static let title: LocalizedStringResource = "빈 종이 플립북 만들기"
    static let description = IntentDescription("팔랑북을 열고 새 빈 종이 플립북을 바로 시작해요.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutRouter.shared.pending = .newBlankFlipbook
        return .result()
    }
}

struct PalangShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewBlankFlipbookIntent(),
            phrases: [
                "\(.applicationName)에서 새 플립북 만들기",
                "\(.applicationName)으로 그림 그리기"
            ],
            shortTitle: "빈 종이 플립북",
            systemImageName: "pencil.and.outline")
    }
}
