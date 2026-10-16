import SwiftUI
import TipKit

/// One-time hints in the editor, each shown only once it's useful: after
/// the first stroke ("now turn the page"), and after a few pages ("add your
/// voice"). Each disappears for good once the button it points at is used.

/// Points at the orange "draw the next picture" button.
struct NextPageTip: Tip {
    /// Donated whenever a stroke or stamp lands on the page.
    static let drewOnPage = Tips.Event(id: "drewOnPage")

    var title: Text { Text("다음 장 그리기") }
    var message: Text? { Text("한 장을 다 그렸으면 주황 버튼을 눌러 다음 그림을 그려요.") }
    var image: Image? { Image(systemName: "pencil.and.outline") }

    var rules: [Rule] {
        #Rule(Self.drewOnPage) { $0.donations.count >= 1 }
    }
}

/// Points at the microphone once a few pages exist — worth a voice by then.
struct DubTip: Tip {
    /// Donated every time the kid moves on to the next page.
    static let turnedPage = Tips.Event(id: "turnedPage")

    var title: Text { Text("목소리 넣기") }
    var message: Text? { Text("마이크를 누르면 그림이 한 번 재생되는 동안 목소리를 녹음해요.") }
    var image: Image? { Image(systemName: "mic.fill") }

    var rules: [Rule] {
        #Rule(Self.turnedPage) { $0.donations.count >= 3 }
    }
}
