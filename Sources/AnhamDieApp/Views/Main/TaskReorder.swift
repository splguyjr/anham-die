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
                if placeBefore {
                    store.reorderTask(id: sourceID, before: targetID)
                } else {
                    store.reorderTask(id: sourceID, after: targetID)
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
