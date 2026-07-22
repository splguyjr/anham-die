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

    private var wakeObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var boundaryTimer: Timer?
    /// 잠금 화면 상태에서 웨이크 트리거가 왔을 때 해제 시점까지 보류
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
        guard shouldShowBriefing(trigger: trigger) else { return }
        if trigger == .wake, isSessionLocked() {
            // 잠금 뒤에서 표시하면 못 본 채 소진되므로 해제 시점까지 보류
            pendingLockedWake = true
            return
        }
        onBriefingRequested?(trigger)
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
                guard let self, self.pendingLockedWake else { return }
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
                self?.scheduleBoundaryTimer()
            }
        }
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
        RunLoop.main.add(timer, forMode: .common)
        boundaryTimer = timer
    }

    private func isSessionLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return dict["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
