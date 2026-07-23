import Foundation
import Testing
@testable import AnhamDieApp

// PLAN §11.7 — 메인 창 프레임 복원의 멀티 스크린 보정. 모니터 분리·배치 변경으로
// 저장 프레임이 화면 밖이 된 경우에도 복원 결과는 반드시 어떤 화면의 visibleFrame
// 안이어야 한다 (visibleFrames 주입은 헤드리스 환경 결정성 제약).

@MainActor
@Suite("메인 창 프레임 화면 보정 (§11.7)")
struct MainWindowFrameValidationTests {
    private let laptop = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let external = CGRect(x: 1440, y: 0, width: 2560, height: 1415)

    @Test("화면 안에 완전히 포함된 프레임은 그대로 유지")
    func containedFrameUnchanged() {
        let frame = CGRect(x: 120, y: 240, width: 780, height: 560)
        #expect(MainWindowState.validatedFrame(frame, visibleFrames: [laptop]) == frame)
    }

    @Test("화면 정보가 없으면(헤드리스) 원본 유지")
    func noScreensKeepsOriginal() {
        let frame = CGRect(x: 5000, y: 5000, width: 780, height: 560)
        #expect(MainWindowState.validatedFrame(frame, visibleFrames: []) == frame)
    }

    @Test("분리된 외장 모니터 좌표의 프레임 → 남은 화면 안으로 클램프")
    func offscreenFrameClampedIntoRemainingScreen() {
        // 외장(x:1440~) 좌표에 저장된 프레임인데 이제 노트북 화면만 남은 시나리오
        let saved = CGRect(x: 2000, y: 300, width: 900, height: 600)
        let result = MainWindowState.validatedFrame(saved, visibleFrames: [laptop])
        #expect(laptop.contains(result))
        #expect(result.size == saved.size)
    }

    @Test("완전 비교차 시 중심이 가장 가까운 화면을 선택")
    func picksNearestScreenWhenNoIntersection() {
        // 외장 오른쪽 밖 좌표 → 노트북보다 외장이 가까움
        let saved = CGRect(x: 4200, y: 200, width: 800, height: 500)
        let result = MainWindowState.validatedFrame(saved, visibleFrames: [laptop, external])
        #expect(external.contains(result))
    }

    @Test("부분 교차 프레임은 해당 화면 안으로 완전히 들어오게 클램프")
    func partiallyOffscreenClampedFullyInside() {
        let saved = CGRect(x: -300, y: 700, width: 780, height: 560)
        let result = MainWindowState.validatedFrame(saved, visibleFrames: [laptop])
        #expect(laptop.contains(result))
        #expect(result.size == saved.size)
    }

    @Test("두 화면과 교차하면 교차 면적이 큰 화면을 선택")
    func picksLargestIntersection() {
        // 경계에 걸친 프레임 — 외장 쪽 교차 면적이 더 큼
        let saved = CGRect(x: 1300, y: 100, width: 800, height: 600)
        let result = MainWindowState.validatedFrame(saved, visibleFrames: [laptop, external])
        #expect(external.contains(result))
    }

    @Test("화면보다 큰 프레임은 visibleFrame 크기로 축소")
    func oversizedFrameShrunkToVisible() {
        let saved = CGRect(x: 1500, y: 100, width: 2560, height: 1415)
        let result = MainWindowState.validatedFrame(saved, visibleFrames: [laptop])
        #expect(laptop.contains(result))
        #expect(result.width == laptop.width)
        #expect(result.height == laptop.height)
    }
}
