import AppKit
import Foundation

/// 메인 창 상태 복원 스텁 (PLAN §11.7) — 저장 키는 AppSettings(mainWindowFrame/
/// mainWindowSelectedView), 여기는 변환·복원 헬퍼만 제공한다.
/// 메인 창 모듈이 연결할 지점:
/// - 창 이동/리사이즈(NSWindow didMove/didResize·windowWillClose) → saveFrame(_:)
/// - 사이드바 selection 변경 → saveSelection(_:)
/// - 창 표시 직전 → restoreFrame()으로 setFrame, restoreSelection(as:)으로 초기 selection
@MainActor
enum MainWindowState {
    /// 프레임 저장 (NSStringFromRect 포맷으로 영속)
    static func saveFrame(_ frame: CGRect, settings: AppSettings = .shared) {
        settings.mainWindowFrame = NSStringFromRect(frame)
    }

    /// 저장된 프레임. 없거나 크기가 0이면 nil (호출부는 defaultSize 유지).
    /// 모니터 분리·배치 변경으로 화면 밖이 된 프레임은 가장 가까운 화면 안으로 보정한다
    /// (OverlayController.positionPanel과 동일 정책) — 호출부(MainWindowConfigurator)가
    /// 반환값을 무조건 setFrame하므로 여기서 반드시 화면 안임을 보장해야 한다.
    static func restoreFrame(settings: AppSettings = .shared) -> CGRect? {
        guard let stored = settings.mainWindowFrame else { return nil }
        let rect = NSRectFromString(stored)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return validatedFrame(rect, visibleFrames: NSScreen.screens.map(\.visibleFrame))
    }

    /// 프레임을 화면 안으로 보정 (visibleFrames 주입은 테스트 결정성 제약).
    /// - 화면 정보 없음(헤드리스 등): 원본 유지
    /// - 어떤 화면이 프레임을 완전히 포함: 원본 유지
    /// - 그 외: 교차 면적 최대 화면(전부 비교차면 중심 최근접 화면)의 visibleFrame에
    ///   맞춰 크기 축소 후 원점 클램프 → 항상 완전히 화면 안
    static func validatedFrame(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard !visibleFrames.isEmpty else { return frame }
        if visibleFrames.contains(where: { $0.contains(frame) }) { return frame }

        let target: CGRect
        let intersecting = visibleFrames.filter { $0.intersects(frame) }
        if let best = intersecting.max(by: {
            intersectionArea($0, frame) < intersectionArea($1, frame)
        }) {
            target = best
        } else {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            target = visibleFrames.min(by: {
                distanceSquared(from: center, to: $0) < distanceSquared(from: center, to: $1)
            })!
        }

        let size = CGSize(
            width: min(frame.width, target.width),
            height: min(frame.height, target.height)
        )
        let maxX = max(target.minX, target.maxX - size.width)
        let maxY = max(target.minY, target.maxY - size.height)
        let origin = CGPoint(
            x: min(max(frame.origin.x, target.minX), maxX),
            y: min(max(frame.origin.y, target.minY), maxY)
        )
        return CGRect(origin: origin, size: size)
    }

    private static func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        return inter.isNull ? 0 : inter.width * inter.height
    }

    private static func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = point.x - min(max(point.x, rect.minX), rect.maxX)
        let dy = point.y - min(max(point.y, rect.minY), rect.maxY)
        return dx * dx + dy * dy
    }

    /// 마지막 선택 사이드바 뷰 저장 — id는 사이드바 selection의 안정적 rawValue 문자열
    static func saveSelection(_ id: String, settings: AppSettings = .shared) {
        settings.mainWindowSelectedView = id
    }

    /// 저장된 사이드바 selection을 RawRepresentable로 복원. 없거나 해석 불가면 nil
    static func restoreSelection<S: RawRepresentable>(
        as type: S.Type, settings: AppSettings = .shared
    ) -> S? where S.RawValue == String {
        settings.mainWindowSelectedView.flatMap(S.init(rawValue:))
    }

    /// 저장된 selection 원시 문자열 (커스텀 selection 타입용)
    static func restoreSelectionRawValue(settings: AppSettings = .shared) -> String? {
        settings.mainWindowSelectedView
    }
}
