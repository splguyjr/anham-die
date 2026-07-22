import SwiftUI

/// 캘린더 뷰 스텁 (PLAN §10.2 — 월간 그리드·드래그는 캘린더 모듈이 이 파일을 대체 구현한다).
struct CalendarView: View {
    var body: some View {
        ListEmptyState(message: "캘린더 뷰 준비 중", systemImage: "calendar")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.surface)
            .navigationTitle("캘린더")
    }
}
