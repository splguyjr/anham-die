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
/// §12.6: '해야할 일' 리스트에서만 소스와 대상이 다른 날짜 그룹이면 정렬이 아니라 날짜 변경(reschedule)으로
/// 위임한다 — 행이 그룹 세로 공간 대부분을 차지하므로 '행 위' 드롭도 날짜 변경 경로로 흘러야 한다.
/// reorderOnly=true(캘린더 일간 뷰/패널·오버레이 등 그 외 컨텍스트)면 날짜 변경 없이 수동 정렬만 한다(v3 동작).
struct TaskReorderDropDelegate: DropDelegate {
    let target: TodoTask
    let store: TaskStore
    let rowHeight: CGFloat
    /// 날짜 간 이동(reschedule) 비활성화 플래그. 기본 true = 수동 정렬만(v3). '해야할 일' 리스트만 false로 넘긴다.
    let reorderOnly: Bool
    @Binding var edge: DropEdge?

    init(
        target: TodoTask,
        store: TaskStore,
        rowHeight: CGFloat,
        reorderOnly: Bool = true,
        edge: Binding<DropEdge?>
    ) {
        self.target = target
        self.store = store
        self.rowHeight = rowHeight
        self.reorderOnly = reorderOnly
        self._edge = edge
    }

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
            let reorderOnly = self.reorderOnly
            let store = self.store
            Task { @MainActor in
                applyRowDrop(
                    sourceID: sourceID,
                    targetID: targetID,
                    placeBefore: placeBefore,
                    reorderOnly: reorderOnly,
                    store: store,
                    boundary: AppContext.shared.dayBoundary
                )
            }
        }
        return true
    }

    /// 드롭 위치가 행의 위쪽 절반이면 앞(top), 아래쪽 절반이면 뒤(bottom).
    private func edge(for info: DropInfo) -> DropEdge {
        rowHeight > 0 && info.location.y > rowHeight / 2 ? .bottom : .top
    }
}

/// 행 드롭의 정렬/날짜변경 결정 (§12.6). performDrop과 유닛 테스트가 공유하는 단일 경로.
/// - reorderOnly=true면 소스·대상 그룹과 무관하게 항상 수동 정렬만 한다
///   (캘린더 일간 뷰/패널·오버레이. `scheduledDate`를 조용히 바꾸던 v3 회귀 방지).
/// - reorderOnly=false('해야할 일' 리스트)면:
///   · 소스가 '언젠가'(someday)이고 대상이 일정 그룹(past/today/upcoming) 안이면 오늘로 꺼낸다
///     (§22.3 pullToToday: scheduledDate=오늘·somedayOrigin=true·rolloverCount 불변). 이어서 드롭 위치에 정렬.
///     대상이 그룹 밖(백로그/완료 리스트 행)이면 꺼내지 않고 순서만 바꾼다.
///   · 그 외 소스는 활성이고 대상과 다른 날짜 그룹일 때만 날짜 변경(reschedule)으로 위임한다.
///     백로그·완료·취소(그룹 없음)나 같은 그룹, past처럼 재배정 날짜가 없어 apply가 reorder로
///     떨어지는 경우는 수동 정렬만 한다(§11.3).
@MainActor
func applyRowDrop(
    sourceID: UUID,
    targetID: UUID,
    placeBefore: Bool,
    reorderOnly: Bool,
    store: TaskStore,
    boundary: DayBoundaryService
) {
    guard sourceID != targetID else { return }
    func reorder() {
        if placeBefore {
            store.reorderTask(id: sourceID, before: targetID)
        } else {
            store.reorderTask(id: sourceID, after: targetID)
        }
    }
    guard !reorderOnly else { reorder(); return }
    guard let source = store.task(withID: sourceID),
          let target = store.task(withID: targetID)
    else { reorder(); return }
    // §22.3: '언젠가' 항목을 '해야할 일' 리스트(일정 그룹 행)로 드래그 → 오늘로 꺼낸다.
    // 대상이 일정 그룹 밖(백로그/완료)이면 pull하지 않고 순서만 바꿔 우발적 이동을 막는다.
    if source.isActive, source.bucket == .someday {
        if store.scheduleGroup(of: target, boundary: boundary) != nil {
            store.pullToToday(source, boundary: boundary)
        }
        reorder()
        return
    }
    guard source.isActive,
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
