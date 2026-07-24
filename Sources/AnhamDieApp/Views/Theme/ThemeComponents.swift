import SwiftUI

/// v5 우선순위 표시 (PLAN §13.4) — 행 리딩 엣지의 세로 색 막대.
/// 높음=빨강(강), 보통=중립(얇은 회색), 낮음=흐림. 태그의 글자 칩(TagPill)과 시각적으로 구별된다.
///
/// 시그니처는 v5 공용 계약(V5-Scaffold) — 소비 모듈이 배치를 담당한다.
/// 막대 높이는 부모가 정하도록 `maxHeight: .infinity`로 늘어난다(행 높이에 맞춤).
/// 폭·둥근 정도만 파라미터로 노출한다.
struct PriorityBar: View {
    let priority: Priority
    var width: CGFloat = 3
    var minHeight: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: width / 2, style: .continuous)
            .fill(AppTheme.priorityBarColor(priority))
            .frame(width: width)
            .frame(minHeight: minHeight, maxHeight: .infinity)
            .accessibilityLabel("우선순위 \(priority.displayName)")
    }
}

/// v5 태그 칩 (PLAN §13.4) — 태그명 텍스트 + 태그 색 배경/테두리의 작은 칩.
/// 색점 방식을 대체한다. 소비 모듈이 트레일링 나열·오버플로("+N")를 담당한다.
///
/// 시그니처는 v5 공용 계약(V5-Scaffold). 색은 태그의 사용자 지정 hex(테마 무관)로 파싱하되,
/// 파싱 실패 시 테마 비활성 텍스트색으로 폴백한다.
struct TagPill: View {
    let name: String
    let colorHex: String

    /// 모델 Tag에서 바로 생성하는 편의 이니셜라이저.
    init(_ tag: Tag) {
        self.name = tag.name
        self.colorHex = tag.colorHex
    }

    init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }

    private var tint: Color {
        ColorHex.color(colorHex) ?? AppTheme.textDisabled
    }

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
            .help(name)
    }
}
