import SwiftUI

/// 사이드바 '포스트잇' 뷰 (v10 §19.2) — 스캐폴드 스텁.
/// 보관함 모듈이 이 파일을 완성한다: 열린 노트 목록 + 보관 노트(닫은 날짜별 그룹),
/// 항목별 본문 미리보기·다시 열기(StickyNotesController.shared.open(note:))·완전 삭제(store.delete).
struct StickyArchiveView: View {
    private var stickies: StickyStore { AppContext.shared.stickies }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.textSecondary)
            Text("포스트잇")
                .font(AppTheme.sectionTitle)
                .foregroundStyle(AppTheme.textPrimary)
            Text("열린 노트 \(stickies.openNotes.count)개 · 보관 \(stickies.archivedNotes.count)개")
                .font(AppTheme.rowMeta)
                .foregroundStyle(AppTheme.textSecondary)
            Button("새 포스트잇") {
                StickyNotesController.shared.createNote()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}
