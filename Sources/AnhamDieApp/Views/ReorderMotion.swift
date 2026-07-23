import SwiftUI

/// 재정렬 스왑 모션 (PLAN §12.7) — 메인 리스트·오버레이가 공유하는 단일 애니메이션 커브.
/// 정렬 결과(sortOrder 영속)·완료 유예 동작은 불변이고, 여기서는 위치 전환만 부드럽게 만든다.
/// 각 행이 자기 sortOrder 변화에 .reorderMotion(value:)로 반응해 점프 없이 스왑되며,
/// 날짜 간 이동(reschedule 등 scheduledDate 구조 변경)을 애니메이션하려는 호출부는 run으로 감싼다.
enum ReorderMotion {
    /// 스왑/이동 공용 커브 — 스프링으로 미끄러지듯 자리 이동(과한 바운스 없음).
    static let animation: Animation = .spring(response: 0.32, dampingFraction: 0.85)

    /// 상태 변경(예: scheduledDate 재배정)을 재정렬 모션 트랜잭션으로 감싼다.
    @MainActor
    static func run(_ body: () -> Void) {
        withAnimation(animation, body)
    }
}

extension View {
    /// value(행: task.sortOrder / 컨테이너: 순서 키)가 바뀔 때만 스왑 애니메이션을 건다 (PLAN §12.7).
    /// value 불변인 변화(호버·편집·완료 유예 등)에는 트랜잭션이 생기지 않아 기존 동작을 건드리지 않는다.
    func reorderMotion<V: Equatable>(value: V) -> some View {
        animation(ReorderMotion.animation, value: value)
    }
}
