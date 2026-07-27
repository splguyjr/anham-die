import SwiftUI

// 리스트 뷰(해야할 일/백로그/완료/캘린더 날짜 패널)가 공유하는 작은 조각들.

struct ListRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.divider.opacity(0.7))
            .frame(height: 1)
    }
}

/// 섹션 헤더: 타이틀(+선택 색상) · 개수 배지
struct ListSectionHeader: View {
    let title: String
    var count: Int?
    var titleColor: Color = AppTheme.textPrimary

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppTheme.sectionTitle)
                .foregroundStyle(titleColor)
            if let count, count > 0 {
                Text("\(count)")
                    .font(AppTheme.badge)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    // 캡슐 채움에 divider 금지 — 글자색 12% 틴트 관례(ThemeContrastTests 잠금).
                    .background(AppTheme.textSecondary.opacity(0.12), in: Capsule())
            }
            Spacer()
        }
        .padding(.top, AppTheme.sectionSpacing)
        .padding(.bottom, 6)
    }
}

struct ListEmptyState: View {
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AppTheme.textDisabled)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// 인라인 추가 행 (체크박스 자리 + 플레이스홀더 텍스트필드, 엔터로 추가)
struct ListAddRow: View {
    let placeholder: String
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
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
        .padding(.vertical, AppTheme.rowVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func submit() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        onSubmit(title)
        text = ""
        focused = true
    }
}
