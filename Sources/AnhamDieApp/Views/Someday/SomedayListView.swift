import SwiftUI

/// '언젠가' 리스트 뷰 (PLAN §22.2) — 백로그와 별개(bucket=someday)의 상시 목록.
/// 상단 추가 행(제목+토큰) → 항목 목록(수동정렬 드래그·[오늘 하기] 토글·완료/삭제·메모 미리보기).
///
/// 데이터 소스는 '언젠가 풀'(store.somedayTasks(): bucket=someday·미완료)에 더해, 오늘로 꺼내둔
/// someday-origin 미완료 항목도 함께 노출한다 — [오늘 하기]가 되돌림 토글(§22.3 returnToSomeday)로
/// 유지되도록. (완료/취소는 isActive에서 걸러져 자연히 빠진다.)
struct SomedayListView: View {
    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }

    /// '언젠가 풀' + '오늘로 꺼내둔 someday-origin' 미완료 항목을 전역 표시 순서로.
    /// - bucket=someday: 풀에 있는 항목(신규·returnToSomeday 복귀분).
    /// - somedayOrigin & 일정 있음: pullToToday로 오늘에 배치된 항목([오늘 하기] 되돌림 토글 대상).
    /// 백로그로 보낸 someday-origin(일정 nil)은 백로그 소관이라 제외 — 두 뷰 중복 노출 방지.
    private var items: [TodoTask] {
        store.tasksInDisplayOrder().filter {
            $0.isActive && ($0.bucket == .someday || ($0.somedayOrigin && $0.scheduledDate != nil))
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // 토큰 문법(#태그 !우선순위) 지원. 날짜 토큰은 '언젠가'에서 무시된다(§22.1).
                MainTokenAddRow(placeholder: "언젠가에 추가", onSubmit: addTask)
                ListRowDivider()
                if items.isEmpty {
                    ListEmptyState(message: "언젠가 할 일이 없습니다", systemImage: "hourglass")
                }
                ForEach(items) { task in
                    SomedayRow(task: task, store: store, boundary: boundary)
                    ListRowDivider()
                }
            }
            .padding(.horizontal, AppTheme.contentPadding)
            .padding(.bottom, 24)
        }
        .background(AppTheme.surface)
        // §17: 메인 리스트 계열에서만 메모 미리보기 opt-in.
        .environment(\.taskRowShowsNotePreview, true)
        .navigationTitle("언젠가")
    }

    private func addTask(_ parse: QuickAddParse) {
        SomedayInlineAdd.commit(parse, store: store)
    }
}
