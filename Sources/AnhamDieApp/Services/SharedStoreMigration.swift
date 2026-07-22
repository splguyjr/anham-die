import Foundation
import Security

/// App Group 공유 컨테이너 상수 및 접근 헬퍼 (PLAN §3.3·§4).
/// 앱과 위젯 익스텐션이 같은 store.json을 공유하기 위한 단일 소스.
/// containerURL은 엔타이틀먼트(com.apple.security.application-groups)가 있어야 non-nil이다 —
/// SPM/ad-hoc 빌드에서는 nil이 정상이며, 이 경우 앱은 기존 Application Support 경로를 유지한다.
enum AppGroup {
    /// 실제 그룹 ID는 Info.plist(AnhamDieAppGroupIdentifier)에서 읽는다 — Xcode 빌드에서
    /// $(TeamIdentifierPrefix) 치환으로 `<TEAMID>.com.splguyjr.anhamdie` 형식이 된다.
    /// (`group.` 접두사는 무료 개인 팀 macOS 프로비저닝에서 동의 프롬프트/조용한 거부를 유발하므로
    /// 팀ID 접두사 형식을 쓴다.) SPM/ad-hoc 빌드는 plist 키가 없어 폴백을 쓰지만
    /// 엔타이틀먼트도 없으므로 containerURL()이 nil이라 실사용되지 않는다.
    static let identifier: String = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AnhamDieAppGroupIdentifier") as? String,
           !value.isEmpty, !value.contains("$(") {
            return value
        }
        return "group.com.splguyjr.anhamdie"
    }()

    /// App Group 컨테이너 루트. 엔타이틀먼트 없거나 접근 불가 시 nil.
    /// 주의: 엔타이틀먼트 없는 ad-hoc 바이너리에서 containerURL(...)을 호출하면 nil 반환이 아니라
    /// containermanagerd XPC에서 무기한 블록될 수 있다(macOS 15 실측 — 앱 시작이 통째로 멈춤).
    /// 반드시 자기 엔타이틀먼트를 먼저 확인하고서만 호출한다.
    static func containerURL() -> URL? {
        guard hasAppGroupEntitlement else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// 현재 프로세스의 서명에 이 그룹의 application-groups 엔타이틀먼트가 있는지
    private static let hasAppGroupEntitlement: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(
            task, "com.apple.security.application-groups" as CFString, nil)
        guard let groups = value as? [String] else { return false }
        return groups.contains(identifier)
    }()

    /// 공유 저장소 디렉토리 (<container>/AnhamDie). 접근 가능할 때만 non-nil.
    static func storeDirectory() -> URL? {
        containerURL()?.appendingPathComponent("AnhamDie", isDirectory: true)
    }

    /// 공유 저장소 파일 (<container>/AnhamDie/store.json).
    static func storeFileURL() -> URL? {
        storeDirectory()?.appendingPathComponent("store.json")
    }

    /// 공유 UserDefaults. 위젯이 하루 기준 시각 등 설정을 읽을 때 사용.
    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}

/// 기존 Application Support 저장소(`~/Library/Application Support/AnhamDie/store.json`)를
/// App Group 컨테이너로 1회 이전한다 (PLAN §8 2차).
/// App Group 컨테이너 접근이 가능(엔타이틀먼트 존재)할 때만 동작하며, 이미 이전됐으면 아무 것도 하지 않는다.
enum SharedStoreMigration {
    private static let migratedFlagKey = "sharedStoreMigrated_v1"

    /// 앱 시작 시 1회 호출한다. 이전이 끝나면(또는 이미 공유 경로를 쓰고 있으면) 공유 저장소 디렉토리를 돌려준다.
    /// - Returns: 앞으로 저장소로 사용할 디렉토리. App Group 접근 불가 시 nil(호출부는 기존 경로 유지).
    @discardableResult
    static func migrateIfNeeded(defaults: UserDefaults = .standard) -> URL? {
        guard let sharedDir = AppGroup.storeDirectory() else { return nil }

        let fm = FileManager.default
        try? fm.createDirectory(at: sharedDir, withIntermediateDirectories: true)

        let sharedStore = sharedDir.appendingPathComponent("store.json")

        // 이미 이전됐거나 공유 저장소가 이미 존재하면 이전을 건너뛴다(공유 데이터 덮어쓰기 방지).
        if defaults.bool(forKey: migratedFlagKey) || fm.fileExists(atPath: sharedStore.path) {
            defaults.set(true, forKey: migratedFlagKey)
            return sharedDir
        }

        let legacyStore = JSONTaskStore.defaultDirectory().appendingPathComponent("store.json")
        if fm.fileExists(atPath: legacyStore.path) {
            do {
                try fm.copyItem(at: legacyStore, to: sharedStore)
            } catch {
                NSLog("AnhamDie: 공유 저장소 이전 실패 — \(error)")
                return sharedDir
            }
        }

        defaults.set(true, forKey: migratedFlagKey)
        return sharedDir
    }
}

// MARK: - 프로세스 간 변경 통지 (앱 ↔ 위젯)

/// 위젯(별도 프로세스)이 store.json을 바꾼 뒤 앱에 알리는 Darwin notification 브리지.
/// Darwin notification은 payload가 없으므로 수신 측(앱)은 디스크를 다시 읽어 머지한다.
enum StoreChangeNotifier {
    /// 위젯 → 앱: 위젯이 완료 토글을 저장한 직후 게시
    static let widgetDidChangeStore = "com.splguyjr.anhamdie.widget.storeChanged"

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }
}

/// Darwin notification 구독 핸들. 살아 있는 동안만 구독이 유지된다.
final class DarwinNotificationObserver {
    private let name: String
    private let handler: () -> Void

    init(name: String, handler: @escaping () -> Void) {
        self.name = name
        self.handler = handler
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { me.handler() }
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            CFNotificationName(name as CFString),
            nil
        )
    }
}
