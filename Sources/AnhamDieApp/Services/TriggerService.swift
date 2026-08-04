import AppKit
import CoreGraphics
import Foundation

/// 브리핑 트리거 판단 (PLAN §2.2). 노출 판단 로직은 여기서 확정.
/// "봤음" 기록(markBriefingShown)은 패널이 실제로 표시되는 시점(BriefingController.show)에서
/// 단일하게 호출된다 — 콜백 미연결/잠금 화면 등으로 못 본 채 그날 브리핑이 소진되는 것을 막는다.
@MainActor
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

    /// 모든 트리거 처리 시 호출되는 부가 경계 훅 (v11 §20.3) — AppContext가
    /// WeeklyReviewService.processWeekTransitionIfNeeded(멱등)를 연결한다.
    /// 새 타이머를 추가하지 않고 기존 하루 경계 경로에 편승한다 (에너지 규약).
    var onTriggerProcessed: (() -> Void)?

    private var wakeObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var boundaryTimer: Timer?
    /// 잠금 화면 상태에서 자동 트리거(웨이크/기준 시각 도달)가 왔을 때 해제 시점까지 보류
    private var pendingLockedWake = false

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

    /// 패널 표시가 확정된 시점(BriefingController.show)에서만 호출할 것
    func markBriefingShown() {
        settings.lastBriefingDate = dayBoundary.now()
    }

    /// 트리거 발생 시 진입점. 노출이 결정되면 콜백 — "봤음" 기록은 표시 측이 담당하므로
    /// 콜백이 없으면 그날 자동 브리핑이 소진되지 않는다.
    func handle(_ trigger: Trigger) {
        // 어떤 트리거든 열려 있는 뷰가 새 논리적 날짜로 재평가되도록 관찰 상태를 먼저 갱신한다.
        refreshCurrentLogicalDay()
        // 주 경계 등 부가 경계 처리(§20.3) — 브리핑 노출 판단·잠금 보류와 무관하게 항상 수행한다
        // (잠금 중 주가 바뀌어도 루틴 재생성이 밀리지 않는다). 연결된 처리는 멱등이어야 한다.
        onTriggerProcessed?()
        guard shouldShowBriefing(trigger: trigger) else { return }
        if trigger == .wake || trigger == .dayBoundary, isSessionLocked() {
            // 잠금 뒤에서 표시하면 못 본 채 소진되므로 해제 시점까지 보류
            // (.dayBoundary도 동일 — 잠금 중 9시 경계 타이머가 발화해도 그날 브리핑을 소진하지 않는다)
            pendingLockedWake = true
            return
        }
        onBriefingRequested?(trigger)
    }

    /// AppSettings.currentLogicalDay(뷰 관찰용 '현재 논리적 날짜')를 최신으로 유지한다.
    /// 경계 타이머·웨이크·잠금 해제·기준 시각 변경 등 논리적 날짜가 바뀔 수 있는 모든 지점에서 호출.
    func refreshCurrentLogicalDay() {
        let today = dayBoundary.logicalToday()
        if settings.currentLogicalDay != today {
            settings.currentLogicalDay = today
        }
    }

    /// 웨이크(슬립 해제)와 기준 시각 도달 트리거를 구독한다.
    /// - NSWorkspace.didWakeNotification → handle(.wake) 후 타이머 재계산(슬립 중엔 타이머가
    ///   발화하지 않으므로 깨어난 시점에 다음 경계로 다시 설치).
    /// - dayBoundary.nextBoundaryDate() 타이머 → handle(.dayBoundary) 후 다음 경계로 재설치.
    /// - 기준 시각 설정 변경 → 타이머 재설치 (옛 시각 타이머 잔존 방지).
    func start() {
        stop()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handle(.wake)
                self.scheduleBoundaryTimer()
            }
        }
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 잠금 중 경계를 넘었을 수 있으므로 보류 여부와 무관하게 날짜를 갱신한다.
                self.refreshCurrentLogicalDay()
                guard self.pendingLockedWake else { return }
                self.pendingLockedWake = false
                self.handle(.wake)
            }
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.dayBoundaryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // 기준 시각이 바뀌면 논리적 오늘 자체가 달라질 수 있다 — 날짜 갱신 후 타이머 재설치.
                self?.refreshCurrentLogicalDay()
                self?.scheduleBoundaryTimer()
                // 기준 시각·주 시작 요일 변경은 현재 주 키도 바꿀 수 있다 — 부가 경계 처리(멱등)를
                // 즉시 태워 주 전환 재처리(§20.3)가 다음 트리거까지 지연되지 않게 한다.
                self?.onTriggerProcessed?()
            }
        }
        refreshCurrentLogicalDay()
        scheduleBoundaryTimer()
    }

    func stop() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let unlockObserver {
            DistributedNotificationCenter.default().removeObserver(unlockObserver)
            self.unlockObserver = nil
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        boundaryTimer?.invalidate()
        boundaryTimer = nil
    }

    private func scheduleBoundaryTimer() {
        boundaryTimer?.invalidate()
        // wall-clock 기준 단발 Timer(fire:) — monotonic 대기와 달리 슬립 후 깨어나면 즉시 발화한다.
        let fireDate = dayBoundary.nextBoundaryDate()
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handle(.dayBoundary)
                self.scheduleBoundaryTimer()
            }
        }
        // 브리핑 트리거는 분 단위 정밀도면 충분 — tolerance를 주어 시스템 타이머 코얼레싱을 허용한다
        // (정확 시각 강제 발화가 그 시점의 웨이크업 병합을 막는 것을 방지).
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        boundaryTimer = timer
    }

    private func isSessionLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return dict["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
