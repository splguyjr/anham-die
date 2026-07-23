import SwiftUI

/// 메인 인라인 추가 행 — 토큰 문법 지원 (PLAN §11.8): 입력 중 #태그·!우선순위·날짜를 실시간 파싱해
/// 아래 칩으로 미리보기하고, Enter 시 토큰 제거된 제목 + 파싱 결과를 onSubmit으로 넘긴다.
/// QuickAddView와 같은 QuickAddTokenParser를 쓴다. 반영(태그 생성·저장)은 호출측(MainInlineAdd).
struct MainTokenAddRow: View {
    let placeholder: String
    let onSubmit: (QuickAddParse) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }

    private var parse: QuickAddParse {
        QuickAddTokenParser.parse(text, tags: store.tags, boundary: boundary)
    }

    private var hasTokens: Bool {
        !parse.tags.isEmpty || parse.priority != nil || parse.date != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: AppTheme.rowSpacing) {
                Image(systemName: text.isEmpty ? "circle" : "circle.badge.plus")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.textDisabled)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(AppTheme.rowTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                    .focused($focused)
                    .onSubmit(submit)
            }
            if hasTokens {
                chipRow
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, AppTheme.rowVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    // MARK: - 칩 미리보기 (읽기 전용)

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(parse.tags, id: \.name) { tag in
                    tagChip(tag)
                }
                if let priority = parse.priority {
                    priorityChip(priority)
                }
                if let date = parse.date {
                    dateChip(date)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func tagChip(_ tag: QuickAddTag) -> some View {
        let color = tag.existingID.flatMap { id in store.tags.first { $0.id == id } }
            .map { AppTheme.tagColor($0.colorHex) } ?? AppTheme.textSecondary
        return chip(background: color.opacity(0.16), stroke: color.opacity(0.5)) {
            MainColorDot(color: color, size: 7)
            Text(tag.name).font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
            if tag.isNew {
                Text("신규").font(.system(size: 9, weight: .bold)).foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private func priorityChip(_ priority: Priority) -> some View {
        let color = AppTheme.priorityColor(priority)
        return chip(background: color.opacity(0.16), stroke: color.opacity(0.5)) {
            Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(color)
            Text(priority.displayName).font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    private func dateChip(_ date: QuickAddDate) -> some View {
        chip(background: AppTheme.accent.opacity(0.16), stroke: AppTheme.accent.opacity(0.5)) {
            Image(systemName: "calendar").font(.system(size: 10)).foregroundStyle(AppTheme.accent)
            Text(date.display).font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    private func chip<Content: View>(
        background: Color,
        stroke: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 5) { content() }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
    }

    private func submit() {
        let parsed = parse
        guard !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSubmit(parsed)
        text = ""
        focused = true
    }
}
