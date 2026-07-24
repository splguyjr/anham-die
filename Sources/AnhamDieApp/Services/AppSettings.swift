import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// 하루 기준 시각 변경 시 게시 — TriggerService(타이머 재설치)와 앱(위젯 리로드)이 구독한다.
    static let dayBoundaryDidChange = Notification.Name("AnhamDie.dayBoundaryDidChange")
    /// 단축키 설정(마스터/개별/예외 앱) 변경 시 게시 — HotkeyService가 구독해 등록 상태를 재적용한다.
    /// 설정 UI는 아래 프로퍼티만 바꾸면 된다 (PLAN §11.4).
    static let hotkeySettingsDidChange = Notification.Name("AnhamDie.hotkeySettingsDidChange")

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
        static let lastUsedDueDate = "lastUsedDueDate"
        static let hotkeysMasterEnabled = "hotkeysMasterEnabled"
        static let disabledHotkeyIDs = "disabledHotkeyIDs"
        static let hotkeyExceptionAppPrefixes = "hotkeyExceptionAppPrefixes"
        static let mainWindowFrame = "mainWindowFrame"
        static let mainWindowSelectedView = "mainWindowSelectedView"
        static let calendarViewMode = "calendarViewMode"
        static let calendarPanelWidth = "calendarPanelWidth"
        static let sidebarCollapsed = "sidebarCollapsed"
        static let selectedThemeID = "selectedThemeID"
        static let accentColorHex = "accentColorHex"
    }

    /// 기본 팔레트 id (ThemePalette.defaultLight.id와 일치) — PLAN §13.2
    static let defaultThemeID = "default"

    /// 예외 앱 목록 기본값 — JetBrains 계열 (PLAN §11.4)
    static let defaultHotkeyExceptionAppPrefixes = ["com.jetbrains."]

    // MARK: - 레이아웃 상태 기본값·범위 (PLAN §12.2·§12.3)

    /// 캘린더 우측 날짜 패널 폭 기본값·클램프 범위 (드래그 조절, §12.2)
    static let calendarPanelWidthDefault: Double = 300
    static let calendarPanelWidthRange: ClosedRange<Double> = 220...560

    @ObservationIgnored private let defaults: UserDefaults

    /// 현재 논리적 날짜(자정 정규화, DayBoundaryService.logicalToday()와 동일 값).
    /// UserDefaults에 저장하지 않는 순수 관찰용 상태 — 경계 타이머·웨이크·기준 시각 변경 시
    /// TriggerService가 갱신하고, 열려 있는 뷰(오버레이·메인 창·브리핑·메뉴바)의 body가 이를 읽어
    /// 경계 통과 순간 '어제'의 오늘 목록이 그대로 남는 문제를 막는다 (PLAN §2·§7).
    /// 초기값은 AppContext 초기화에서 넣는다.
    var currentLogicalDay: Date = .distantPast

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

    /// 최근 설정한 마감일 (PLAN §10.7 — 날짜 UI의 [최근: M/d] 원클릭 칩·달력 초기 표시 달).
    /// scheduledDate/dueDate와 같은 '자정 날짜 키' 규약 — 쓰기 시 DayBoundaryService.scheduledDateValue(for:)를 거칠 것.
    var lastUsedDueDate: Date? {
        didSet {
            if let d = lastUsedDueDate {
                defaults.set(d, forKey: Keys.lastUsedDueDate)
            } else {
                defaults.removeObject(forKey: Keys.lastUsedDueDate)
            }
        }
    }

    // MARK: - 전역 단축키 (PLAN §11.4)

    /// 마스터 토글: 전역 단축키 전체 on/off (기본 on)
    var hotkeysMasterEnabled: Bool {
        didSet {
            defaults.set(hotkeysMasterEnabled, forKey: Keys.hotkeysMasterEnabled)
            NotificationCenter.default.post(name: Self.hotkeySettingsDidChange, object: self)
        }
    }
    /// 개별 토글: 꺼진 단축키의 KeyboardShortcuts.Name.rawValue 집합 (기본 전부 켬 = 빈 집합)
    var disabledHotkeyIDs: Set<String> {
        didSet {
            defaults.set(Array(disabledHotkeyIDs).sorted(), forKey: Keys.disabledHotkeyIDs)
            NotificationCenter.default.post(name: Self.hotkeySettingsDidChange, object: self)
        }
    }
    /// 예외 앱: 이 접두사로 시작하는 번들 ID의 앱이 frontmost일 때 전역 단축키 전체 양보.
    /// 정확한 번들 ID도 자기 자신의 접두사이므로 그대로 넣으면 된다. 기본 ["com.jetbrains."]
    var hotkeyExceptionAppPrefixes: [String] {
        didSet {
            defaults.set(hotkeyExceptionAppPrefixes, forKey: Keys.hotkeyExceptionAppPrefixes)
            NotificationCenter.default.post(name: Self.hotkeySettingsDidChange, object: self)
        }
    }

    // MARK: - 메인 창 상태 (PLAN §11.7)

    /// 메인 창 프레임 (NSStringFromRect 포맷 문자열). nil = 저장된 프레임 없음
    var mainWindowFrame: String? {
        didSet {
            if let f = mainWindowFrame {
                defaults.set(f, forKey: Keys.mainWindowFrame)
            } else {
                defaults.removeObject(forKey: Keys.mainWindowFrame)
            }
        }
    }
    /// 마지막 선택 사이드바 뷰 식별자 (사이드바 selection의 rawValue). nil = 기본 뷰
    var mainWindowSelectedView: String? {
        didSet {
            if let v = mainWindowSelectedView {
                defaults.set(v, forKey: Keys.mainWindowSelectedView)
            } else {
                defaults.removeObject(forKey: Keys.mainWindowSelectedView)
            }
        }
    }

    // MARK: - 캘린더·레이아웃 상태 (PLAN §12.1·§12.2·§12.3)

    /// 캘린더 월/주/일 뷰 모드 (§12.1). rawValue 문자열로 영속.
    var calendarViewMode: CalendarViewMode {
        didSet { defaults.set(calendarViewMode.rawValue, forKey: Keys.calendarViewMode) }
    }
    /// 캘린더 우측 날짜 패널 폭 (§12.2). 쓰기 시 calendarPanelWidthRange로 클램프해 저장.
    var calendarPanelWidth: Double {
        didSet {
            let clamped = min(max(calendarPanelWidth, Self.calendarPanelWidthRange.lowerBound),
                              Self.calendarPanelWidthRange.upperBound)
            if clamped != calendarPanelWidth {
                calendarPanelWidth = clamped
                return
            }
            defaults.set(calendarPanelWidth, forKey: Keys.calendarPanelWidth)
        }
    }
    /// 좌측 사이드바 접힘 상태 (§12.3).
    var sidebarCollapsed: Bool {
        didSet { defaults.set(sidebarCollapsed, forKey: Keys.sidebarCollapsed) }
    }

    // MARK: - 색상 테마 (PLAN §13.2)

    /// 선택 프리셋 팔레트 id (ThemePalette.preset(for:)로 해석, 미상 id는 기본 폴백).
    var selectedThemeID: String {
        didSet { defaults.set(selectedThemeID, forKey: Keys.selectedThemeID) }
    }
    /// 강조색 오버라이드 "#RRGGBB". nil = 팔레트 기본 강조색 사용(ColorPicker 미설정).
    var accentColorHex: String? {
        didSet {
            if let hex = accentColorHex {
                defaults.set(hex, forKey: Keys.accentColorHex)
            } else {
                defaults.removeObject(forKey: Keys.accentColorHex)
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
        self.lastUsedDueDate = defaults.object(forKey: Keys.lastUsedDueDate) as? Date
        self.hotkeysMasterEnabled = defaults.object(forKey: Keys.hotkeysMasterEnabled) as? Bool ?? true
        self.disabledHotkeyIDs = Set(defaults.stringArray(forKey: Keys.disabledHotkeyIDs) ?? [])
        self.hotkeyExceptionAppPrefixes = defaults.stringArray(forKey: Keys.hotkeyExceptionAppPrefixes)
            ?? Self.defaultHotkeyExceptionAppPrefixes
        self.mainWindowFrame = defaults.string(forKey: Keys.mainWindowFrame)
        self.mainWindowSelectedView = defaults.string(forKey: Keys.mainWindowSelectedView)
        self.calendarViewMode = (defaults.string(forKey: Keys.calendarViewMode)
            .flatMap(CalendarViewMode.init(rawValue:))) ?? .month
        self.calendarPanelWidth = defaults.object(forKey: Keys.calendarPanelWidth) as? Double
            ?? Self.calendarPanelWidthDefault
        self.sidebarCollapsed = defaults.object(forKey: Keys.sidebarCollapsed) as? Bool ?? false
        self.selectedThemeID = defaults.string(forKey: Keys.selectedThemeID) ?? Self.defaultThemeID
        self.accentColorHex = defaults.string(forKey: Keys.accentColorHex)
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
