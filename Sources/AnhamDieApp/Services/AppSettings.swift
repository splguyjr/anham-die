import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    enum Keys {
        static let dayBoundaryHour = "dayBoundaryHour"
        static let dayBoundaryMinute = "dayBoundaryMinute"
        static let showDockIcon = "showDockIcon"
        static let launchAtLogin = "launchAtLogin"
        static let overlayOpacity = "overlayOpacity"
        static let overlayMaxCount = "overlayMaxCount"
        static let overlayPositionX = "overlayPositionX"
        static let overlayPositionY = "overlayPositionY"
        static let overlayVisible = "overlayVisible"
        static let lastBriefingDate = "lastBriefingDate"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// 논리적 하루 기준 시각 (기본 09:00)
    var dayBoundaryHour: Int {
        didSet { defaults.set(dayBoundaryHour, forKey: Keys.dayBoundaryHour) }
    }
    var dayBoundaryMinute: Int {
        didSet { defaults.set(dayBoundaryMinute, forKey: Keys.dayBoundaryMinute) }
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
        self.overlayMaxCount = defaults.object(forKey: Keys.overlayMaxCount) as? Int ?? 7
        if let x = defaults.object(forKey: Keys.overlayPositionX) as? Double,
           let y = defaults.object(forKey: Keys.overlayPositionY) as? Double {
            self.overlayPosition = CGPoint(x: x, y: y)
        } else {
            self.overlayPosition = nil
        }
        self.overlayVisible = defaults.object(forKey: Keys.overlayVisible) as? Bool ?? false
        self.lastBriefingDate = defaults.object(forKey: Keys.lastBriefingDate) as? Date
    }
}
