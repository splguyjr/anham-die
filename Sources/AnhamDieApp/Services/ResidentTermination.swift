import Foundation

/// 자동 종료(Automatic Termination) 제어의 테스트 시임 — ProcessInfo가 그대로 채택한다.
protocol AutomaticTerminationControlling {
    func disableAutomaticTermination(_ reason: String)
}

extension ProcessInfo: AutomaticTerminationControlling {}

/// 메뉴바 상주(LSUIElement) 앱이 macOS 자동 종료로 조용히 꺼지지 않도록 막는다 (PLAN §18).
/// SwiftUI 씬이 자동 종료를 켜므로, 마지막 창을 닫고 유휴가 되면 OS가 ~14초 뒤 Quit AppleEvent
/// (applicationShouldTerminate 경로)로 프로세스를 종료시킨다. v9가 창 닫기를 1차 동선으로 만들어
/// 이 조건 노출이 잦아졌다. applicationShouldTerminateAfterLastWindowClosed=false는 이 경로를
/// 막지 못한다 — 자동 종료는 별개 스위치라 disableAutomaticTermination 카운터로만 끌 수 있고,
/// Quit AppleEvent 출처(사용자 ⌘Q vs OS TAL)는 구분 불가하므로 자동 종료 자체를 끈다.
enum ResidentTermination {
    /// 자동 종료 비활성 사유(카운터 키). balancing enable 호출 없이 앱 수명 동안 유지한다.
    static let reason = "메뉴바 상주"

    /// 앱 시작 시 1회 호출 — 자동 종료 카운터를 올려 유휴 프로세스가 종료되지 않게 한다.
    static func keepResident(_ process: AutomaticTerminationControlling = ProcessInfo.processInfo) {
        process.disableAutomaticTermination(reason)
    }
}
