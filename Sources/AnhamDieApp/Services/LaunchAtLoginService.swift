import Foundation
import ServiceManagement

/// SMAppService 로그인 항목의 단일 진입점.
/// register는 반드시 `isRunningFromApplications` 확인 후 호출할 것 —
/// dist/·swift run 같은 임시 경로가 BTM에 등록되면 다음 빌드의 rm -rf로 경로가 사라져
/// 깨진 로그인 항목(시스템 알림 반복)이 남는다.
@MainActor
enum LaunchAtLoginService {
    /// 실행 중인 번들이 로그인 항목 등록이 허용되는 설치 위치(/Applications, ~/Applications 하위)인지.
    static var isRunningFromApplications: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func register() throws {
        try SMAppService.mainApp.register()
    }

    static func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
