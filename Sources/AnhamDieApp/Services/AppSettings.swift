import Foundation
import Observation

/// 오버레이 체크박스 클릭 동작 (PLAN §3.4 "오버레이 투명도·클릭 동작")
enum OverlayClickAction: String, CaseIterable, Identifiable {
    case completeImmediately
    case openApp
    case ignore

    var id: String { rawValue }

    var label: String {
        switch self {
        case .completeImmediately: "즉시 완료 체크"
        case .openApp: "메인 창 열기"
        case .ignore: "무시"
        }
    }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// 하루 기준 시각 변경 시 게시 — TriggerService(타이머 재설치)와 앱(위젯 리로드)이 구독한다.
    static let dayBoundaryDidChange = Notification.Name("AnhamDie.dayBoundaryDidChange")

    enum Keys {
        static let dayBoundaryHour = "dayBoundaryHour"
        static let dayBoundaryMinute = "dayBoundaryMinute"
        static let showDockIcon = "showDockIcon"
        static let launchAtLogin = "launchAtLogin"
        static let overlayOpacity = "overlayOpacity"
        static let overlayClickAction = "overlayClickAction"
        static let overlayMaxCount = "overlayMaxCount"
        static let overlayPositionX = "overlayPositionX"
        static let overlayPositionY = "overlayPositionY"
        static let overlayVisible = "overlayVisible"
        static let lastBriefingDate = "lastBriefingDate"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// 논리적 하루 기준 시각 (기본 09:00).
    /// 위젯(별도 프로세스)이 같은 "논리적 오늘"을 계산하도록 App Group suite에도 미러링한다.
    var dayBoundaryHour: Int {
        didSet {
            defaults.set(dayBoundaryHour, forKey: Keys.dayBoundaryHour)
            mirrorDayBoundaryToSharedDefaults()
            NotificationCenter.default.post(name: Self.dayBoundaryDidChange, object: self)
        }
    }
    var dayBoundaryMinute: Int {
        didSet {
            defaults.set(dayBoundaryMinute, forKey: Keys.dayBoundaryMinute)
            mirrorDayBoundaryToSharedDefaults()
            NotificationCenter.default.post(name: Self.dayBoundaryDidChange, object: self)
        }
    }
    var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Keys.showDockIcon) }
    }
    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    /// 오버레이 배경 불투명도 0.0~1.0 (기본 0.9)
    var overlayOpacity: Double {
        didSet { defaults.set(overlayOpacity, forKey: Keys.overlayOpacity) }
    }
    /// 오버레이 체크박스 클릭 동작 (기본: 즉시 완료 체크)
    var overlayClickAction: OverlayClickAction {
        didSet { defaults.set(overlayClickAction.rawValue, forKey: Keys.overlayClickAction) }
    }
    /// 오버레이 최대 표시 개수 (기본 7, 초과분 "+N개")
    var overlayMaxCount: Int {
        didSet { defaults.set(overlayMaxCount, forKey: Keys.overlayMaxCount) }
    }
    /// 오버레이 좌하단 기준 화면 좌표. nil = 저장된 위치 없음
    var overlayPosition: CGPoint? {
        didSet {
            if let p = overlayPosition {
                defaults.set(Double(p.x), forKey: Keys.overlayPositionX)
                defaults.set(Double(p.y), forKey: Keys.overlayPositionY)
            } else {
                defaults.removeObject(forKey: Keys.overlayPositionX)
                defaults.removeObject(forKey: Keys.overlayPositionY)
            }
        }
    }
    var overlayVisible: Bool {
        didSet { defaults.set(overlayVisible, forKey: Keys.overlayVisible) }
    }
    /// 마지막으로 브리핑을 자동 표시한 시각. 논리적 날짜 비교는 TriggerService가 담당
    var lastBriefingDate: Date? {
        didSet {
            if let d = lastBriefingDate {
                defaults.set(d, forKey: Keys.lastBriefingDate)
            } else {
                defaults.removeObject(forKey: Keys.lastBriefingDate)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.dayBoundaryHour = defaults.object(forKey: Keys.dayBoundaryHour) as? Int ?? 9
        self.dayBoundaryMinute = defaults.object(forKey: Keys.dayBoundaryMinute) as? Int ?? 0
        self.showDockIcon = defaults.object(forKey: Keys.showDockIcon) as? Bool ?? false
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.overlayOpacity = defaults.object(forKey: Keys.overlayOpacity) as? Double ?? 0.9
        self.overlayClickAction = defaults.string(forKey: Keys.overlayClickAction)
            .flatMap(OverlayClickAction.init(rawValue:)) ?? .completeImmediately
        self.overlayMaxCount = defaults.object(forKey: Keys.overlayMaxCount) as? Int ?? 7
        if let x = defaults.object(forKey: Keys.overlayPositionX) as? Double,
           let y = defaults.object(forKey: Keys.overlayPositionY) as? Double {
            self.overlayPosition = CGPoint(x: x, y: y)
        } else {
            self.overlayPosition = nil
        }
        self.overlayVisible = defaults.object(forKey: Keys.overlayVisible) as? Bool ?? false
        self.lastBriefingDate = defaults.object(forKey: Keys.lastBriefingDate) as? Date
        mirrorDayBoundaryToSharedDefaults()
    }

    /// App Group suite가 접근 가능할 때만 기준 시각을 복사한다.
    /// 번들 ID 없는 실행(swift run/테스트)은 공유 suite를 오염시키지 않도록 제외.
    private func mirrorDayBoundaryToSharedDefaults() {
        guard Bundle.main.bundleIdentifier?.hasPrefix("com.splguyjr.anhamdie") == true,
              let shared = AppGroup.sharedDefaults(), shared !== defaults else { return }
        shared.set(dayBoundaryHour, forKey: Keys.dayBoundaryHour)
        shared.set(dayBoundaryMinute, forKey: Keys.dayBoundaryMinute)
    }
}
