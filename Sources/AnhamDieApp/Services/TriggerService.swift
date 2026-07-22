import Foundation

/// 브리핑 트리거 판단 (PLAN §2.2). 노출 판단 로직은 여기서 확정.
/// NSWorkspace.didWakeNotification 구독과 기준 시각 타이머 설치는 briefing 모듈이
/// start()를 완성하며 채운다. 트리거 발생 시 handle(_:)만 호출하면 된다.
final class TriggerService {
    enum Trigger {
        case appLaunch
        case wake
        case dayBoundary
        /// 단축키/메뉴바 수동 호출 — 판단 없이 항상 표시
        case hotkey
    }

    private let settings: AppSettings
    private let dayBoundary: DayBoundaryService

    /// 브리핑 패널을 실제로 띄우는 쪽(BriefingController)이 연결한다
    var onBriefingRequested: ((Trigger) -> Void)?

    init(settings: AppSettings, dayBoundary: DayBoundaryService) {
        self.settings = settings
        self.dayBoundary = dayBoundary
    }

    /// 자동 트리거는 논리적 오늘 아직 브리핑을 안 봤을 때만 true. hotkey는 항상 true.
    func shouldShowBriefing(trigger: Trigger) -> Bool {
        if case .hotkey = trigger { return true }
        guard let last = settings.lastBriefingDate else { return true }
        return dayBoundary.logicalDate(of: last) < dayBoundary.logicalToday()
    }

    func markBriefingShown() {
        settings.lastBriefingDate = dayBoundary.now()
    }

    /// 트리거 발생 시 진입점. 노출이 결정되면 lastBriefingDate 갱신 후 콜백.
    func handle(_ trigger: Trigger) {
        guard shouldShowBriefing(trigger: trigger) else { return }
        markBriefingShown()
        onBriefingRequested?(trigger)
    }

    /// briefing 모듈이 완성: NSWorkspace.shared.notificationCenter의 didWakeNotification 구독
    /// (→ handle(.wake)) + dayBoundary.nextBoundaryDate() 타이머 설치 (→ handle(.dayBoundary),
    /// 발화 후 다음 경계로 재설치. 웨이크 시 타이머 재계산 필요)
    func start() {
        // 스켈레톤 — briefing 모듈 소유
    }

    func stop() {
        // 스켈레톤 — briefing 모듈 소유
    }
}
