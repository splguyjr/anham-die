import SwiftUI

/// 공용 날짜 선택 컴포넌트 (PLAN §10.7). 상세 뷰의 마감일과 행 호버/컨텍스트의 날짜 액션 양쪽에서 쓴다.
/// [오늘][내일][최근 M/d] 원클릭 칩 + [달력](인라인 그래픽 DatePicker, 최근 설정한 달로 열림) + [지우기].
/// 값은 '자정 날짜 키' 규약(DayBoundaryService.scheduledDateValue)으로 정규화해 바인딩에 넣고,
/// 설정 시 settings.lastUsedDueDate를 갱신한다 — 다음 등록 때 [최근] 칩·달력 시작 달의 소스가 된다.
struct DueDateControls: View {
    @Binding var date: Date?
    let boundary: DayBoundaryService
    let settings: AppSettings
    var allowsClear: Bool = true
    /// 값 반영 후 추가로 실행할 훅 (바인딩 setter에서 이미 저장한다면 생략 가능).
    var onChange: (() -> Void)? = nil

    @State private var showCalendar = false

    private static let md: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d"
        return f
    }()

    private var today: Date { boundary.scheduledDateValue(for: boundary.logicalToday()) }
    private var tomorrow: Date {
        let d = boundary.calendar.date(byAdding: .day, value: 1, to: boundary.logicalToday())!
        return boundary.scheduledDateValue(for: d)
    }
    /// 현재 값을 날짜 키로 정규화 (칩 선택 표시 비교용)
    private var dateKey: Date? { date.map { boundary.scheduledDateValue(for: $0) } }

    /// [최근] 칩에 노출할 날짜 — 오늘/내일과 겹치면 중복이라 숨긴다.
    private var recentDate: Date? {
        guard let recent = settings.lastUsedDueDate else { return nil }
        let key = boundary.scheduledDateValue(for: recent)
        if key == today || key == tomorrow { return nil }
        return key
    }

    private var calendarBinding: Binding<Date> {
        Binding(
            get: { date ?? settings.lastUsedDueDate ?? today },
            set: { set($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("오늘", selected: dateKey == today) { set(today) }
                    chip("내일", selected: dateKey == tomorrow) { set(tomorrow) }
                    if let recent = recentDate {
                        chip("최근 \(Self.md.string(from: recent))", selected: dateKey == recent) { set(recent) }
                    }
                    chip("달력", systemImage: "calendar", selected: showCalendar) {
                        withAnimation(.easeOut(duration: 0.15)) { showCalendar.toggle() }
                    }
                    if allowsClear && date != nil {
                        // §21.10: 동작은 백로그 이동(scheduledDate=nil)인데 "지우기"는 삭제로 오해된다.
                        // 라벨·아이콘(tray)을 동작에 맞춰 삭제와 시각적으로 구분한다. 동작 자체는 불변.
                        chip("날짜 비우기 · 백로그", systemImage: "tray", selected: false) {
                            set(nil)
                            showCalendar = false
                        }
                    }
                }
                .padding(.vertical, 1)
            }

            if showCalendar {
                DatePicker("", selection: calendarBinding, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ko_KR"))
                    .frame(maxWidth: 280)
            }
        }
    }

    private func set(_ value: Date?) {
        if let value {
            let normalized = boundary.scheduledDateValue(for: value)
            date = normalized
            settings.lastUsedDueDate = normalized
        } else {
            date = nil
        }
        onChange?()
    }

    @ViewBuilder
    private func chip(
        _ label: String,
        systemImage: String? = nil,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? Color.white : AppTheme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(selected ? AppTheme.accent : AppTheme.accent.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
