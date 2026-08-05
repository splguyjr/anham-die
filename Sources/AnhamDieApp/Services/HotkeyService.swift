import AppKit
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 브리핑 토글 ⌥⌘T (PLAN §7)
    static let toggleBriefing = Self("toggleBriefing", default: .init(.t, modifiers: [.option, .command]))
    /// 오버레이 토글 ⌥⌘O
    static let toggleOverlay = Self("toggleOverlay", default: .init(.o, modifiers: [.option, .command]))
    /// 빠른 추가 ⌥⌘N
    static let quickAdd = Self("quickAdd", default: .init(.n, modifiers: [.option, .command]))
    /// 메인 창 열기/포커스 ⌥⌘M (PLAN §10.3)
    static let openMain = Self("openMain", default: .init(.m, modifiers: [.option, .command]))
    /// 새 포스트잇 ⌥⌘S (PLAN §19.3)
    static let newSticky = Self("newSticky", default: .init(.s, modifiers: [.option, .command]))
    /// 열린 포스트잇 전체 표시/숨김 토글 ⌥⌘H (PLAN §19.3)
    static let toggleStickies = Self("toggleStickies", default: .init(.h, modifiers: [.option, .command]))
    /// '언젠가' 패널 토글 ⌥⌘L (PLAN §22.2). 핸들러(패널 토글)는 모듈이 onToggleSomeday로 연결한다.
    static let toggleSomeday = Self("toggleSomeday", default: .init(.l, modifiers: [.option, .command]))
}

/// 전역 단축키 등록·suspend/resume의 단일 소스 (PLAN §11.4).
/// - 마스터 토글·개별 토글·예외 앱 목록은 AppSettings가 저장하고, 변경 시
///   hotkeySettingsDidChange 알림으로 이 서비스가 재적용한다 — 설정 UI는 설정만 바꾸면 된다.
/// - 예외 앱: frontmost 앱의 번들 ID가 예외 접두사와 일치하는 동안 전역 등록을 일괄 suspend
///   (KeyboardShortcuts.isEnabled), 벗어나면 resume. 마스터 off도 같은 스위치를 쓴다.
/// - 개별 토글은 KeyboardShortcuts.disable/enable(이름별)로 반영된다.
@MainActor
final class HotkeyService {
    static let shared = HotkeyService(settings: AppSettings.shared)

    /// 설정 UI가 나열하는 전체 단축키 (표시 순서 = 설정 탭 순서)
    static let allNames: [KeyboardShortcuts.Name] = [
        .toggleBriefing, .toggleOverlay, .quickAdd, .openMain, .newSticky, .toggleStickies,
        .toggleSomeday,
    ]

    /// 단축키의 한국어 표시명 (설정 UI 공용)
    static func displayName(for name: KeyboardShortcuts.Name) -> String {
        switch name {
        case .toggleBriefing: return "브리핑 토글"
        case .toggleOverlay: return "오버레이 토글"
        case .quickAdd: return "빠른 추가"
        case .openMain: return "메인 창 열기/닫기 토글"
        case .newSticky: return "새 포스트잇"
        case .toggleStickies: return "포스트잇 전체 표시/숨김"
        case .toggleSomeday: return "언젠가 패널 토글"
        default: return name.rawValue
        }
    }

    private let settings: AppSettings
    /// '언젠가' 패널 토글 핸들러 (PLAN §22.2). Name·등록·개별 토글은 스캐폴드가 소유하고,
    /// 실제 동작(패널 토글)은 담당 모듈이 여기 연결한다 — 스캐폴드가 패널 타입에 의존하지 않게 한다.
    /// setup() 이후에 설정돼도 onKeyUp 핸들러가 호출 시점에 읽으므로 지연 연결이 안전하다.
    var onToggleSomeday: (() -> Void)?
    private var frontmostObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    /// setup() 재진입 방지 — onKeyUp 핸들러가 이름당 배열에 append되므로 두 번 등록되면 토글이 이중 발화한다.
    private var didSetup = false
    /// frontmost 앱이 예외 목록에 걸려 있는 동안 true
    private(set) var suspendedByFrontmostApp = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 번들 ID가 예외 접두사 목록에 해당하는가 (대소문자 무시 접두사 일치)
    nonisolated static func isExempt(bundleID: String?, prefixes: [String]) -> Bool {
        guard let bundleID = bundleID?.lowercased() else { return false }
        return prefixes.contains { prefix in
            let p = prefix.trimmingCharacters(in: .whitespaces).lowercased()
            return !p.isEmpty && bundleID.hasPrefix(p)
        }
    }

    /// didFinishLaunching 이후에 호출할 것 — KeyboardShortcuts.Name 최초 참조가 이보다 이르면
    /// Carbon 등록만 되고 핸들러 없는 좀비 핫키가 된다 (v1 회귀 노트).
    func setup() {
        guard !didSetup else { return }
        didSetup = true
        KeyboardShortcuts.onKeyUp(for: .toggleBriefing) {
            Task { @MainActor in BriefingController.shared.toggle() }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleOverlay) {
            Task { @MainActor in OverlayController.shared.toggle() }
        }
        KeyboardShortcuts.onKeyUp(for: .quickAdd) {
            Task { @MainActor in QuickAddController.shared.show() }
        }
        KeyboardShortcuts.onKeyUp(for: .openMain) {
            Task { @MainActor in MainWindowOpener.toggle() }
        }
        KeyboardShortcuts.onKeyUp(for: .newSticky) {
            Task { @MainActor in StickyNotesController.shared.createNote() }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleStickies) {
            Task { @MainActor in StickyNotesController.shared.toggleAllVisible() }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleSomeday) { [weak self] in
            Task { @MainActor in self?.onToggleSomeday?() }
        }

        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated {
                self?.frontmostAppDidChange(bundleID: bundleID)
            }
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.hotkeySettingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }

        // 시작 시 초기 상태를 1회 확정한다(개별 토글·마스터 상태 적용). 이후 앱 전환은
        // suspend 상태가 실제로 바뀔 때만 refresh()한다.
        suspendedByFrontmostApp = Self.isExempt(
            bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            prefixes: settings.hotkeyExceptionAppPrefixes
        )
        refresh()
    }

    /// 설정(마스터/개별/예외 앱) 변경·frontmost 변경 후 등록 상태 재적용
    func refresh() {
        applyMasterState()
        applyPerHotkeyState()
    }

    private func frontmostAppDidChange(bundleID: String?) {
        // 앱 전환마다 refresh()하지 않는다 — suspend 값이 실제로 바뀔 때만 재적용해
        // 전환당 UserDefaults 읽기·JSONDecoder 생성·enable/disable 반복을 없앤다.
        let newValue = Self.isExempt(
            bundleID: bundleID, prefixes: settings.hotkeyExceptionAppPrefixes
        )
        guard newValue != suspendedByFrontmostApp else { return }
        suspendedByFrontmostApp = newValue
        refresh()
    }

    private func applyMasterState() {
        KeyboardShortcuts.isEnabled = settings.hotkeysMasterEnabled && !suspendedByFrontmostApp
    }

    private func applyPerHotkeyState() {
        for name in Self.allNames {
            if settings.disabledHotkeyIDs.contains(name.rawValue) {
                KeyboardShortcuts.disable(name)
            } else {
                KeyboardShortcuts.enable(name)
            }
        }
    }
}
