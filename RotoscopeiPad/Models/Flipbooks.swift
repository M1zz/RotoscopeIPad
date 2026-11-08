import Foundation

/// 움직이는 그림(동영상 · 따라 그리기 — 여러 장을 그려 재생하는 것)은
/// 어른이 설정에서 연다. 꺼져 있으면 아이에게는 빈 종이 스케치북만 보인다.
@MainActor
enum Flipbooks {
    static let key = "flipbooksOpen"

    /// Before this switch existed every kid made flipbooks: an iPad that
    /// already has works keeps them open. Call once, before any view reads it.
    static func openForExistingUsers() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(!RotoProject.listProjects().isEmpty, forKey: key)
    }
}
