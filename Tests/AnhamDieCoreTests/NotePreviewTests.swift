import Foundation
import Testing
@testable import AnhamDieApp

// PLAN §17 — 메모 미리보기: 설정 키 왕복 + 첫 줄 추출 헬퍼.

@MainActor
@Suite("메모 미리보기 설정 (§17)")
struct NotePreviewSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "AnhamDieTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("기본값은 켜짐(true)")
    func defaultOn() {
        let defaults = freshDefaults()
        #expect(AppSettings(defaults: defaults).showNotePreview == true)
    }

    @Test("showNotePreview 라운드트립")
    func roundTrips() {
        let defaults = freshDefaults()
        let s = AppSettings(defaults: defaults)
        s.showNotePreview = false
        #expect(AppSettings(defaults: defaults).showNotePreview == false)
        s.showNotePreview = true
        #expect(AppSettings(defaults: defaults).showNotePreview == true)
    }
}

@Suite("메모 첫 줄 추출 (§17)")
struct NotePreviewFirstLineTests {
    @Test("빈 메모는 nil")
    func emptyIsNil() {
        #expect(NotePreview.firstLine("") == nil)
        #expect(NotePreview.firstLine("   ") == nil)
        #expect(NotePreview.firstLine("\n\n") == nil)
    }

    @Test("한 줄 메모는 트리밍해 그대로")
    func singleLine() {
        #expect(NotePreview.firstLine("  살 것 정리  ") == "살 것 정리")
    }

    @Test("여러 줄 메모는 첫 줄만")
    func multiLineTakesFirst() {
        #expect(NotePreview.firstLine("우유 사기\n계란 사기\n빵") == "우유 사기")
    }

    @Test("선행 빈 줄은 건너뛰고 첫 내용 줄")
    func skipsLeadingBlankLines() {
        #expect(NotePreview.firstLine("\n  \n실제 내용\n둘째 줄") == "실제 내용")
    }

    @Test("CRLF 개행도 첫 줄만")
    func handlesCRLF() {
        #expect(NotePreview.firstLine("첫 줄\r\n둘째 줄") == "첫 줄")
    }
}
