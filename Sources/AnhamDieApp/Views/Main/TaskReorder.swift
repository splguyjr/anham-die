import SwiftUI
import UniformTypeIdentifiers

/// 행 드래그 수동 정렬 (PLAN §11.3·§11.6): 드래그한 행을 대상 행의 앞/뒤로 이동한다.
/// 순서는 스토어 단일 API(reorderTask(id:before:)/after:)로 영속되며 전 뷰(메인·오버레이·브리핑·위젯)에 반영된다.
/// 필터·섹션된 목록 안에서도 전역 순서 기준으로 안전하다(스토어가 보장).
enum DropEdge: Equatable { case top, bottom }

/// 드래그 소스가 실을 페이로드 — task.id의 UUID 문자열 (public.text로 등록).
@MainActor
func taskDragItemProvider(_ task: TodoTask) -> NSItemProvider {
    NSItemProvider(object: task.id.uuidString as NSString)
}

/// 행 드롭 대상 델리게이트. 드롭 위치(위/아래 절반)로 대상 행의 앞/뒤 삽입을 결정한다.
/// §12.6: 소스와 대상이 다른 날짜 그룹이면 정렬이 아니라 날짜 변경(reschedule)으로 위임한다 —
/// 행이 그룹 세로 공간 대부분을 차지하므로 '행 위' 드롭도 날짜 변경 경로로 흘러야 한다.
struct TaskReorderDropDelegate: DropDelegate {
    let target: TodoTask
    let store: TaskStore
    let rowHeight: CGFloat
    @Binding var edge: DropEdge?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        edge = edge(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        edge = edge(for: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        edge = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let placeBefore = edge(for: info) == .top
        edge = nil
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let targetID = target.id
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String, let sourceID = UUID(uuidString: string) else { return }
            Task { @MainActor in
                guard sourceID != targetID else { return }
                let boundary = AppContext.shared.dayBoundary
                @MainActor func reorder() {
                    if placeBefore {
                        store.reorderTask(id: sourceID, before: targetID)
                    } else {
                        store.reorderTask(id: sourceID, after: targetID)
                    }
                }
                // §12.6: 소스가 활성 태스크이고 대상과 다른 날짜 그룹이면 날짜 변경(reschedule)으로 위임한다.
                // 그룹이 없거나(백로그·완료·취소) 같은 그룹, 또는 past처럼 재배정 날짜가 없어 apply가
                // reorder로 떨어지는 경우는 수동 정렬만 한다(§11.3·v3 회귀 방지).
                guard let source = store.task(withID: sourceID),
                      let target = store.task(withID: targetID),
                      source.isActive,
                      let from = store.scheduleGroup(of: source, boundary: boundary),
                      let to = store.scheduleGroup(of: target, boundary: boundary),
                      from != to
                else { reorder(); return }
                if case .reorder = ScheduleDrag.apply(
                    dragged: source, from: from, to: to, store: store, boundary: boundary
                ) {
                    reorder()
                }
            }
        }
        return true
    }

    /// 드롭 위치가 행의 위쪽 절반이면 앞(top), 아래쪽 절반이면 뒤(bottom).
    private func edge(for info: DropInfo) -> DropEdge {
        rowHeight > 0 && info.location.y > rowHeight / 2 ? .bottom : .top
    }
}

/// 드롭 삽입 위치를 알리는 얇은 액센트 선 (행 위/아래 가장자리).
struct TaskReorderIndicator: View {
    let edge: DropEdge?

    var body: some View {
        VStack(spacing: 0) {
            line.opacity(edge == .top ? 1 : 0)
            Spacer(minLength: 0)
            line.opacity(edge == .bottom ? 1 : 0)
        }
        .allowsHitTesting(false)
    }

    private var line: some View {
        Rectangle()
            .fill(AppTheme.accent)
            .frame(height: 2)
    }
}
