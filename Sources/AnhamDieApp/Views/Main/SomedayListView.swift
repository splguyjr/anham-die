import SwiftUI

/// '언젠가' 리스트 뷰 (PLAN §22.2) — v13 스캐폴드 스텁.
/// 담당 모듈이 추가/편집·수동정렬·[오늘 하기]·해야할일 드래그·완료/삭제·메모 미리보기를 얹는다.
/// 데이터 소스는 store.somedayTasks() (bucket=someday & 미완료), 오늘로 꺼내기는 store.pullToToday(_:boundary:).
struct SomedayListView: View {
    private var store: TaskStore { AppContext.shared.store }

    var body: some View {
        let items = store.somedayTasks()
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "언젠가 할 일이 없습니다",
                    systemImage: "hourglass",
                    description: Text("여유될 때 꾸준히 해나갈 일을 여기에 모아두세요.")
                )
            } else {
                List(items) { task in
                    Text(task.title)
                        .font(AppTheme.rowTitle)
                }
            }
        }
        .navigationTitle("언젠가")
    }
}
