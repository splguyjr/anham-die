import SwiftUI

/// 캘린더 뷰 v2 (PLAN §10.2): 월간 7열 그리드 + 날짜별 task, task 드래그로 scheduledDate 변경,
/// 날짜 클릭 시 우측 그 날 목록 패널, 월 이동(←/→/오늘). AppTheme 적용.
struct CalendarView: View {
    /// 표시 중인 달(1일 자정). nil이면 논리적 오늘의 달을 보여준다.
    @State private var displayedMonth: Date?
    @State private var selectedDay: Date?
    @State private var dropTargetDay: Date?

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }
    private var calendar: Calendar { boundary.calendar }

    private let cellSpacing: CGFloat = 4
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: cellSpacing), count: 7)
    }

    var body: some View {
        // 논리적 하루 경계 통과 시 재평가 (오늘 강조·overdue 색이 다음 날 밀리지 않도록 — §2·§7).
        let _ = AppContext.shared.settings.currentLogicalDay
        let today = boundary.logicalToday()
        let month = displayedMonth ?? monthStart(of: today)
        let layout = MonthLayout(containing: month, calendar: calendar)

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                monthHeader(layout)
                weekdayHeader(layout)
                gridArea(layout, today: today)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let day = selectedDay {
                Divider()
                CalendarDayPanel(
                    day: day,
                    store: store,
                    boundary: boundary,
                    onClose: { withAnimation(.easeInOut(duration: 0.18)) { selectedDay = nil } }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(AppTheme.surface)
        .navigationTitle("캘린더")
    }

    // MARK: - 헤더

    private func monthHeader(_ layout: MonthLayout) -> some View {
        HStack(spacing: 10) {
            Text(CalendarFormatters.monthTitle.string(from: layout.monthStart))
                .font(AppTheme.windowTitle)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Button("오늘") { goToday() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(AppTheme.divider))
            navButton(systemImage: "chevron.left") { shiftMonth(-1) }
            navButton(systemImage: "chevron.right") { shiftMonth(1) }
        }
        .padding(.bottom, 10)
    }

    private func navButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 26, height: 26)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(AppTheme.divider))
        }
        .buttonStyle(.plain)
    }

    private func weekdayHeader(_ layout: MonthLayout) -> some View {
        HStack(spacing: cellSpacing) {
            ForEach(Array(layout.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CalendarPalette.weekdayColor(weekday(forColumn: index), base: AppTheme.textSecondary))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - 그리드

    private func gridArea(_ layout: MonthLayout, today: Date) -> some View {
        GeometryReader { geo in
            let cellHeight = max(46, (geo.size.height - CGFloat(layout.rows - 1) * cellSpacing) / CGFloat(layout.rows))
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: cellSpacing) {
                    ForEach(layout.days, id: \.self) { day in
                        cell(day, layout: layout, today: today, cellHeight: cellHeight)
                    }
                }
            }
        }
    }

    private func cell(_ day: Date, layout: MonthLayout, today: Date, cellHeight: CGFloat) -> some View {
        CalendarDayCell(
            day: day,
            tasks: store.tasks(on: day, boundary: boundary),
            isInMonth: layout.isInMonth(day, calendar: calendar),
            isToday: day == today,
            isSelected: selectedDay == day,
            isDropTarget: dropTargetDay == day,
            isPast: day < today,
            cellHeight: cellHeight,
            calendar: calendar,
            onSelect: { select(day) }
        )
        .dropDestination(for: CalendarTaskDrag.self) { items, _ in
            handleDrop(items, on: day)
        } isTargeted: { targeted in
            if targeted {
                dropTargetDay = day
            } else if dropTargetDay == day {
                dropTargetDay = nil
            }
        }
    }

    // MARK: - 액션

    private func select(_ day: Date) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedDay = (selectedDay == day) ? nil : day
        }
    }

    /// 드롭한 task의 scheduledDate를 대상 날짜로 변경 (v1 자정 날짜 키 규약: scheduledDateValue).
    private func handleDrop(_ items: [CalendarTaskDrag], on day: Date) -> Bool {
        dropTargetDay = nil
        guard let item = items.first, let task = store.task(withID: item.taskID) else { return false }
        task.scheduledDate = boundary.scheduledDateValue(for: day)
        store.notifyChanged()
        return true
    }

    private func shiftMonth(_ delta: Int) {
        let base = displayedMonth ?? monthStart(of: boundary.logicalToday())
        if let shifted = calendar.date(byAdding: .month, value: delta, to: base) {
            withAnimation(.easeInOut(duration: 0.15)) {
                displayedMonth = monthStart(of: shifted)
            }
        }
    }

    private func goToday() {
        let today = boundary.logicalToday()
        withAnimation(.easeInOut(duration: 0.18)) {
            displayedMonth = monthStart(of: today)
            selectedDay = today
        }
    }

    // MARK: - 헬퍼

    private func monthStart(of date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            ?? calendar.startOfDay(for: date)
    }

    /// 그리드 열 index(0~6)에 해당하는 요일(1=일 ... 7=토)
    private func weekday(forColumn index: Int) -> Int {
        ((calendar.firstWeekday - 1 + index) % 7) + 1
    }
}
