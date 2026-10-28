//
//  RotoscopeiPadRoadmap.swift
//  RotoscopeiPad
//
//  **앞으로 만들 것**의 원본. 설정 ▸ 지원 ▸ 앞으로 만들 기능(`LeeoRoadmapView`)이 이 목록을 그대로 보여 준다.
//
//  ⚠️ 개발하다 "이건 다음에" 가 생기면 **여기에 한 줄을 더한다.** 코드의 TODO 주석으로만 남기지 않는다.
//     - 새 항목: `.planned`. 손대기 시작하면 `.building`. 내보내면 `.shipped("1.3.0")`.
//     - id 는 한 번 정하면 바꾸지 않는다(문구는 바꿔도 된다). 같은 피처는 다른 앱과 같은 id 를 쓴다.
//     - 문구는 사용자 말로 쓴다(내부 이름 · 기술 용어 금지). 번역은 `Localizable.xcstrings` 에 모든 언어를 채운다.
//     - 사용자에게 보일 만한 것만 적는다. 리팩터링 · 시험 · 빌드 설정은 `.sprintcommander/tasks.json` 의 몫이다.
//     - 설정은 보호자 확인 뒤에만 열리므로 문구는 어른에게 하는 말로 쓴다.
//

import SwiftUI
import LeeoKit

extension RotoscopeiPadSpec {
    static var roadmap: [LeeoRoadmapItem] {[
        // MARK: 만들고 있어요
        .init(id: "gift", status: .building,
              title: NSLocalizedString("평생 이용권 선물하기", comment: "Roadmap item: gift the lifetime pass"),
              detail: NSLocalizedString("내가 결제하면, 고른 사람이 모든 기능을 평생 쓸 수 있어요.", comment: "Roadmap item detail: gift the lifetime pass")),

        // MARK: 다음에 만들어요
        .init(id: "a11y.voiceover", status: .planned,
              title: NSLocalizedString("VoiceOver로 더 편하게", comment: "Roadmap item: better VoiceOver support"),
              detail: NSLocalizedString("화면 읽기 기능이 단추와 그리기 도구를 빠짐없이, 알맞은 순서로 읽어 줘요.", comment: "Roadmap item detail: better VoiceOver support")),
        .init(id: "a11y.largetext", status: .planned,
              title: NSLocalizedString("큰 글씨에 맞춘 화면", comment: "Roadmap item: Dynamic Type layouts"),
              detail: NSLocalizedString("글자 크기를 키워도 잘리지 않고 보기 좋게 다시 배치돼요.", comment: "Roadmap item detail: Dynamic Type layouts")),
        .init(id: "display.dark", status: .planned,
              title: NSLocalizedString("다크 모드", comment: "Roadmap item: dark mode"),
              detail: NSLocalizedString("어두운 화면에서도 글자와 단추가 또렷하게 보여요.", comment: "Roadmap item detail: dark mode")),
        .init(id: "a11y.contrast", status: .planned,
              title: NSLocalizedString("보기 편한 색과 대비", comment: "Roadmap item: contrast and color"),
              detail: NSLocalizedString("대비를 높이거나 색을 구별하기 어려워도 내용을 알아볼 수 있어요.", comment: "Roadmap item detail: contrast and color")),
        .init(id: "a11y.motion", status: .planned,
              title: NSLocalizedString("움직임 줄이기", comment: "Roadmap item: reduce motion"),
              detail: NSLocalizedString("움직임 줄이기를 켜면 화면 효과가 차분해져요.", comment: "Roadmap item detail: reduce motion")),
        .init(id: "whatsnew", status: .planned,
              title: NSLocalizedString("업데이트 소식", comment: "Roadmap item: what's new"),
              detail: NSLocalizedString("업데이트 뒤 처음 열 때 무엇이 새로 생겼는지 알려 줘요.", comment: "Roadmap item detail: what's new")),
        .init(id: "widgets", status: .planned,
              title: NSLocalizedString("홈 화면 위젯", comment: "Roadmap item: home screen widgets"),
              detail: NSLocalizedString("앱을 열지 않고 홈 화면에서 아이 작품을 바로 봐요.", comment: "Roadmap item detail: home screen widgets")),
        .init(id: "sync.icloud", status: .planned,
              title: NSLocalizedString("기기 간 동기화", comment: "Roadmap item: iCloud sync"),
              detail: NSLocalizedString("다른 아이패드에서도 그리던 작품을 이어서 그려요.", comment: "Roadmap item detail: iCloud sync")),
        .init(id: "backup", status: .planned,
              title: NSLocalizedString("작품 백업하기", comment: "Roadmap item: backup and export"),
              detail: NSLocalizedString("작품을 파일로 저장해 두고 언제든 다시 불러와요.", comment: "Roadmap item detail: backup and export")),
        .init(id: "data.delete", status: .planned,
              title: NSLocalizedString("작품 한 번에 지우기", comment: "Roadmap item: delete all data"),
              detail: NSLocalizedString("원하면 앱 안의 작품을 한 번에 모두 지울 수 있어요.", comment: "Roadmap item detail: delete all data")),
    ]}
}

// MARK: - 화면

/// 설정 ▸ 앞으로 만들 기능. "이런 기능이 있으면 좋겠어요" 는 기능 제안으로 시작하는 피드백 창을 연다.
struct RoadmapScreen: View {
    @State private var showFeedback = false

    var body: some View {
        LeeoRoadmapView<RotoscopeiPadSpec>(onSuggest: { showFeedback = true })
            .sheet(isPresented: $showFeedback) {
                NavigationStack {
                    LeeoFeedbackView<RotoscopeiPadSpec>(initialType: .feature)
                }
            }
    }
}
