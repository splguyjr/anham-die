import Foundation
import Security

/// App Group 공유 컨테이너 상수 및 접근 헬퍼 (PLAN §3.3·§4).
/// 앱과 위젯 익스텐션이 같은 store.json을 공유하기 위한 단일 소스.
/// containerURL은 엔타이틀먼트(com.apple.security.application-groups)가 있어야 non-nil이다 —
/// SPM/ad-hoc 빌드에서는 nil이 정상이며, 이 경우 앱은 기존 Application Support 경로를 유지한다.
enum AppGroup {
    /// 그룹 ID는 자기 서명의 application-groups 엔타이틀먼트에서 파생한다 —
    /// `$(TeamIdentifierPrefix)` 치환은 엔타이틀먼트 처리 단계에서만 보장되고
    /// Info.plist 빌드설정 확장에서는 정의되지 않아 빈 문자열이 될 수 있으므로
    /// (프로비저닝 프로파일 없는 macOS 개발 서명에서 특히) plist 값은 신뢰하지 않는다.
    /// 엔타이틀먼트에서 읽으면 앱·위젯이 확장 여부와 무관하게 항상 같은 값을 쓴다.
    /// (`group.` 접두사가 아닌 팀ID 접두사 형식인 이유: `group.`은 무료 개인 팀
    /// macOS 프로비저닝에서 동의 프롬프트/조용한 거부를 유발한다.)
    /// SPM/ad-hoc 빌드는 엔타이틀먼트가 없어 nil — 앱은 기존 Application Support 경로를 유지한다.
    static let identifier: String? = {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(
                  task, "com.apple.security.application-groups" as CFString, nil) as? [String]
        else { return nil }
        let candidates = groups.filter { !$0.contains("$(") }
        guard let group = candidates.first(where: { $0.hasSuffix("com.splguyjr.anhamdie") })
            ?? candidates.first
        else { return nil }
        if let plistValue = Bundle.main.object(
               forInfoDictionaryKey: "AnhamDieAppGroupIdentifier") as? String,
           plistValue != group {
            NSLog("AnhamDie: Info.plist AnhamDieAppGroupIdentifier(%@)가 엔타이틀먼트 그룹(%@)과 다릅니다 — 엔타이틀먼트 값을 사용합니다.",
                  plistValue, group)
        }
        return group
    }()

    /// App Group 컨테이너 루트. 엔타이틀먼트 없거나 접근 불가 시 nil.
    /// 주의: 엔타이틀먼트 없는 ad-hoc 바이너리에서 containerURL(...)을 호출하면 nil 반환이 아니라
    /// containermanagerd XPC에서 무기한 블록될 수 있다(macOS 15 실측 — 앱 시작이 통째로 멈춤).
    /// identifier가 엔타이틀먼트에서 파생되므로 non-nil이면 호출해도 안전하다.
    static func containerURL() -> URL? {
        guard let identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

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
        identifier.flatMap { UserDefaults(suiteName: $0) }
    }
}

/// 기존 Application Support 저장소(`~/Library/Application Support/AnhamDie/store.json`)를
/// App Group 컨테이너로 1회 이전한다 (PLAN §8 2차).
/// App Group 컨테이너 접근이 가능(엔타이틀먼트 존재)할 때만 동작하며, 이미 이전됐으면 아무 것도 하지 않는다.
enum SharedStoreMigration {
    private static let migratedFlagKey = "sharedStoreMigrated_v1"

    /// 앱 시작 시 1회 호출한다. 이전이 끝나면(또는 이미 공유 경로를 쓰고 있으면) 공유 저장소 디렉토리를 돌려준다.
    /// - Returns: 앞으로 저장소로 사용할 디렉토리.
    ///   App Group 접근 불가 시 또는 이전 복사 실패 시 nil(호출부는 기존 경로 유지).
    ///   복사 실패 시 공유 경로를 돌려주면 앱이 빈 공유 저장소로 기동하고, 종료 시 saveNow()가
    ///   빈 store.json을 공유 경로에 만들어 다음 실행부터 이전이 영구 스킵된다(데이터 소실 체감) —
    ///   그래서 실패 시 반드시 nil을 돌려주고 다음 실행에서 재시도한다.
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
                // 부분 복사 잔해가 남으면 다음 실행의 fileExists 분기가 이전을 영구 스킵하므로 제거한다.
                try? fm.removeItem(at: sharedStore)
                // 플래그 미설정 + nil 반환 → 이번 세션은 레거시 경로 유지, 다음 실행에서 이전 재시도.
                return nil
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
