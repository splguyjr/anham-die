import Testing
@testable import AnhamDieApp

// PLAN §18 — 메뉴바 상주 앱이 OS 자동 종료로 꺼지지 않도록 시작 시 자동 종료를 끈다.
// 실제 ProcessInfo 카운터는 관측 불가하므로, 시임에 사유가 정확히 1회 전달되는지 검증한다.

@Suite("상주 앱 자동 종료 방지 (§18)")
struct ResidentTerminationTests {
    final class SpyProcess: AutomaticTerminationControlling {
        var reasons: [String] = []
        func disableAutomaticTermination(_ reason: String) { reasons.append(reason) }
    }

    @Test("keepResident는 자동 종료를 사유와 함께 정확히 1회 끈다")
    func disablesOnceWithReason() {
        let spy = SpyProcess()
        ResidentTermination.keepResident(spy)
        #expect(spy.reasons == [ResidentTermination.reason])
    }

    @Test("사유는 비어 있지 않다 (카운터 키로 유효)")
    func reasonNotEmpty() {
        #expect(!ResidentTermination.reason.isEmpty)
    }
}
