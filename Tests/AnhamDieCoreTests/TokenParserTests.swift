import Foundation
import Testing
@testable import AnhamDieApp

// MARK: - 퀵애드 토큰 파서 (PLAN §10.8)

@MainActor
@Suite("QuickAddTokenParser")
struct QuickAddTokenParserTests {
    // 논리적 오늘 = 2026-07-22 (경계 09:00, 현재 10:00)
    private let today = midnight(2026, 7, 22)
    private let tomorrow = midnight(2026, 7, 23)
    private let dayAfter = midnight(2026, 7, 24)
    private let boundary: DayBoundaryService

    init() {
        boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
    }

    private func parse(_ raw: String, tags: [TaskTag] = []) -> QuickAddParse {
        QuickAddTokenParser.parse(raw, tags: tags, boundary: boundary)
    }

    @Test("토큰이 없으면 제목만 그대로 반환")
    func plainTitle() {
        let p = parse("장보기 목록 정리")
        #expect(p.title == "장보기 목록 정리")
        #expect(p.tags.isEmpty)
        #expect(p.priority == nil)
        #expect(p.date == nil)
    }

    @Test("#태그는 제목에서 제거되고 태그로 인식된다")
    func tagRemovedFromTitle() {
        let p = parse("회의 준비 #업무")
        #expect(p.title == "회의 준비")
        #expect(p.tags.map { $0.name } == ["업무"])
    }

    @Test("기존 태그면 existingID가 채워지고, 없으면 생성 대상(nil)")
    func existingVsNewTag() {
        let existing = TaskTag(name: "업무")
        let p = parse("보고서 #업무 #개인", tags: [existing])
        #expect(p.tags.count == 2)
        #expect(p.tags[0].name == "업무")
        #expect(p.tags[0].existingID == existing.id)
        #expect(p.tags[0].isNew == false)
        #expect(p.tags[1].name == "개인")
        #expect(p.tags[1].existingID == nil)
        #expect(p.tags[1].isNew == true)
    }

    @Test("기존 태그 매칭은 대소문자를 무시하고 저장된 표기를 쓴다")
    func tagMatchCaseInsensitive() {
        let existing = TaskTag(name: "Work")
        let p = parse("todo #work", tags: [existing])
        #expect(p.tags.map { $0.name } == ["Work"])
        #expect(p.tags[0].existingID == existing.id)
    }

    @Test("같은 태그를 두 번 쓰면 한 번만 남는다")
    func tagDeduped() {
        let p = parse("작업 #A #a #A")
        #expect(p.tags.map { $0.name } == ["A"])
    }

    @Test("!높음/!보통/!낮음 우선순위 인식")
    func priorityKorean() {
        #expect(parse("x !높음").priority == .high)
        #expect(parse("x !보통").priority == .normal)
        #expect(parse("x !낮음").priority == .low)
    }

    @Test("!1/!2/!3 우선순위 별칭 (1=높음, 3=낮음)")
    func priorityNumericAlias() {
        #expect(parse("x !1").priority == .high)
        #expect(parse("x !2").priority == .normal)
        #expect(parse("x !3").priority == .low)
    }

    @Test("우선순위가 여러 개면 마지막이 이긴다")
    func priorityLastWins() {
        #expect(parse("x !높음 !낮음").priority == .low)
    }

    @Test("인식 불가한 ! 토큰은 제목으로 남는다")
    func unknownBangStaysInTitle() {
        let p = parse("가격 !중요 확인")
        #expect(p.priority == nil)
        #expect(p.title == "가격 !중요 확인")
    }

    @Test("오늘/내일/모레 날짜 인식")
    func relativeDates() {
        #expect(parse("x 오늘").date?.value == today)
        #expect(parse("x 내일").date?.value == tomorrow)
        #expect(parse("x 모레").date?.value == dayAfter)
        #expect(parse("x 내일").date?.display == "내일")
    }

    @Test("M/d 날짜 인식 (올해)")
    func slashDateThisYear() {
        let p = parse("행사 12/25")
        #expect(p.date?.value == midnight(2026, 12, 25))
        #expect(p.date?.display == "12/25")
        #expect(p.title == "행사")
    }

    @Test("이미 지난 M/d는 내년으로 넘어간다")
    func slashDateRollsToNextYear() {
        let p = parse("신년 1/1")
        #expect(p.date?.value == midnight(2027, 1, 1))
    }

    @Test("M월 d일 (공백 분리)와 M월d일 (붙임) 모두 인식")
    func koreanMonthDay() {
        let spaced = parse("발표 7월 25일")
        #expect(spaced.date?.value == midnight(2026, 7, 25))
        #expect(spaced.title == "발표")

        let joined = parse("발표 7월25일")
        #expect(joined.date?.value == midnight(2026, 7, 25))
        #expect(joined.title == "발표")
    }

    @Test("존재하지 않는 날짜(2/30)는 제목으로 남는다")
    func invalidDateStaysInTitle() {
        let p = parse("메모 2/30")
        #expect(p.date == nil)
        #expect(p.title == "메모 2/30")
    }

    @Test("복합 입력: 제목·태그·우선순위·날짜 동시 파싱")
    func combined() {
        let existing = TaskTag(name: "업무")
        let p = parse("분기 보고서 #업무 !높음 내일 #긴급", tags: [existing])
        #expect(p.title == "분기 보고서")
        #expect(p.tags.map { $0.name } == ["업무", "긴급"])
        #expect(p.tags[0].existingID == existing.id)
        #expect(p.tags[1].isNew)
        #expect(p.priority == .high)
        #expect(p.date?.value == tomorrow)
    }

    // MARK: - 자동완성

    @Test("작성 중 태그 조각 감지 (문자열 끝의 미완성 # 토큰)")
    func activeFragmentDetected() {
        #expect(QuickAddTokenParser.activeTagFragment(in: "회의 #업") == "업")
        #expect(QuickAddTokenParser.activeTagFragment(in: "회의 #") == "")
    }

    @Test("공백으로 끝나거나 태그 입력 중이 아니면 조각 없음")
    func noActiveFragment() {
        #expect(QuickAddTokenParser.activeTagFragment(in: "회의 #업무 ") == nil)
        #expect(QuickAddTokenParser.activeTagFragment(in: "회의 준비") == nil)
        #expect(QuickAddTokenParser.activeTagFragment(in: "") == nil)
        #expect(QuickAddTokenParser.activeTagFragment(in: "a#b") == nil)
    }

    @Test("부분일치 후보 — prefix 일치가 앞, excluding 제외")
    func suggestions() {
        let tags = [TaskTag(name: "업무"), TaskTag(name: "개업"), TaskTag(name: "회의")]
        let hits = QuickAddTokenParser.tagSuggestions(for: "업", in: tags)
        #expect(hits.map { $0.name } == ["업무", "개업"]) // prefix "업무"가 부분일치 "개업"보다 앞

        let excluded = QuickAddTokenParser.tagSuggestions(for: "업", in: tags, excluding: ["업무"])
        #expect(excluded.map { $0.name } == ["개업"])
    }

    @Test("빈 조각은 전체 태그를 후보로 반환")
    func emptyFragmentSuggestsAll() {
        let tags = [TaskTag(name: "업무"), TaskTag(name: "회의")]
        let hits = QuickAddTokenParser.tagSuggestions(for: "", in: tags)
        #expect(Set(hits.map { $0.name }) == ["업무", "회의"])
    }

    @Test("작성 중 조각을 고른 태그로 치환하고 공백을 붙인다")
    func replaceFragment() {
        #expect(QuickAddTokenParser.replacingActiveTagFragment(in: "회의 #업", with: "업무") == "회의 #업무 ")
        // 활성 조각이 없으면 원문 유지
        #expect(QuickAddTokenParser.replacingActiveTagFragment(in: "회의 #업무 완료", with: "업무") == "회의 #업무 완료")
    }
}
