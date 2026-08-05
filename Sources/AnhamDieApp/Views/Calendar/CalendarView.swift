import AppKit
import SwiftUI

/// 캘린더 뷰 v4 (PLAN §12.1·§12.2): 상단 월/주/일 전환 세그먼트 + 뷰 단위 오늘/◀/▶ 이동.
/// 월간 = 창 높이에 맞춘 셀(셀당 3~4개 + "+N개"), 주간 = 일~토 7열 + 열 간 드래그 reschedule,
/// 일간 = 넓은 단일일 리스트(제목 전체). 우측 날짜 패널은 경계 드래그로 폭 조절(calendarPanelWidth 저장·복원).
struct CalendarView: View {
    /// 현재 뷰의 기준 날짜(자정). nil이면 논리적 오늘. ◀/▶는 뷰 단위로 이 값을 옮긴다.
    @State private var anchorDate: Date?
    /// 우측 날짜 패널에 표시할 선택 날짜(월/주 뷰 전용). nil이면 패널 닫힘.
    @State private var selectedDay: Date?
    @State private var dropTargetDay: Date?
    /// 패널 폭 드래그 시작 시점의 폭 — translation을 절대 폭으로 환산하기 위한 앵커(§12.2).
    @State private var panelDragStartWidth: Double?

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }
    private var settings: AppSettings { AppContext.shared.settings }
    private var calendar: Calendar { boundary.calendar }

    private let cellSpacing: CGFloat = 4
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: cellSpacing), count: 7)
    }

    var body: some View {
        // 논리적 하루 경계 통과 시 재평가 (오늘 강조·overdue 색이 다음 날 밀리지 않도록 — §2·§7).
        let _ = settings.currentLogicalDay
        let mode = settings.calendarViewMode
        let today = boundary.logicalToday()
        let anchor = anchorDate ?? today

        VStack(spacing: 0) {
            header(mode: mode, anchor: anchor)
            Divider()
            content(mode: mode, anchor: anchor, today: today)
        }
        .background(AppTheme.surface)
        .navigationTitle("캘린더")
    }

    // MARK: - 헤더 (뷰 전환 세그먼트 + 이동)

    private func header(mode: CalendarViewMode, anchor: Date) -> some View {
        HStack(spacing: 10) {
            Text(headerTitle(mode: mode, anchor: anchor))
                .font(AppTheme.windowTitle)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Picker("", selection: viewModeBinding) {
                ForEach(CalendarViewMode.allCases, id: \.self) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Button("오늘") { goToday() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(AppTheme.divider))
            navButton(systemImage: "chevron.left") { shift(-1) }
            navButton(systemImage: "chevron.right") { shift(1) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func headerTitle(mode: CalendarViewMode, anchor: Date) -> String {
        switch mode {
        case .month:
            return CalendarFormatters.monthTitle.string(from: monthStart(of: anchor))
        case .week:
            let layout = WeekLayout(containing: anchor, calendar: calendar)
            return CalendarFormatters.weekRangeTitle(
                start: layout.days.first ?? anchor,
                end: layout.days.last ?? anchor,
                calendar: calendar
            )
        case .day:
            return CalendarFormatters.dayViewTitle.string(from: anchor)
        }
    }

    private var viewModeBinding: Binding<CalendarViewMode> {
        Binding(
            get: { settings.calendarViewMode },
            set: { newMode in
                withAnimation(.easeInOut(duration: 0.15)) { settings.calendarViewMode = newMode }
            }
        )
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

    // MARK: - 본문 (뷰별)

    @ViewBuilder
    private func content(mode: CalendarViewMode, anchor: Date, today: Date) -> some View {
        switch mode {
        case .month:
            HStack(spacing: 0) {
                monthBody(anchor: anchor, today: today)
                rightPanel
            }
        case .week:
            HStack(spacing: 0) {
                CalendarWeekView(
                    anchor: anchor,
                    today: today,
                    store: store,
                    boundary: boundary,
                    selectedDay: selectedDay,
                    onSelectDay: { select($0) }
                )
                rightPanel
            }
        case .day:
            CalendarDayView(day: anchor, store: store, boundary: boundary)
        }
    }

    // MARK: - 월간 그리드

    private func monthBody(anchor: Date, today: Date) -> some View {
        let layout = MonthLayout(containing: monthStart(of: anchor), calendar: calendar)
        return VStack(spacing: 0) {
            // §21.6: 월간 진입에서도 이번 주(현재 월이면 라이브, 다른 월이면 해당 주 기록) 목표 진행이 보이도록
            // 그리드 위에 주간 뷰와 공용인 목표 스트립을 얹는다. 탭 → 주간 목표 뷰로 이동.
            CalendarGoalStrip(
                weekStart: boundary.weekStart(ofDay: anchor),
                store: store,
                boundary: boundary,
                onOpenGoals: { CalendarNavigation.openWeeklyGoals() }
            )
            Divider()
            VStack(spacing: 0) {
                weekdayHeader(layout)
                gridArea(layout, today: today)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func gridArea(_ layout: MonthLayout, today: Date) -> some View {
        GeometryReader { geo in
            // 셀 높이를 창 높이에 맞춰 키운다 (§12.1). 표시 개수는 높이에 비례해 3~4개까지.
            let cellHeight = max(64, (geo.size.height - CGFloat(layout.rows - 1) * cellSpacing) / CGFloat(layout.rows))
            let maxVisible = min(4, max(2, Int((cellHeight - 30) / 16)))
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: cellSpacing) {
                    ForEach(layout.days, id: \.self) { day in
                        cell(day, layout: layout, today: today, cellHeight: cellHeight, maxVisible: maxVisible)
                    }
                }
            }
        }
    }

    private func cell(_ day: Date, layout: MonthLayout, today: Date, cellHeight: CGFloat, maxVisible: Int) -> some View {
        CalendarDayCell(
            day: day,
            tasks: store.tasks(on: day, boundary: boundary),
            isInMonth: layout.isInMonth(day, calendar: calendar),
            isToday: day == today,
            isSelected: selectedDay == day,
            isDropTarget: dropTargetDay == day,
            isPast: day < today,
            cellHeight: cellHeight,
            maxVisible: maxVisible,
            calendar: calendar,
            onSelect: { select(day) }
        )
        .dropDestination(for: CalendarTaskDrag.self) { items, _ in
            reschedule(items, to: day)
        } isTargeted: { targeted in
            if targeted {
                dropTargetDay = day
            } else if dropTargetDay == day {
                dropTargetDay = nil
            }
        }
    }

    // MARK: - 우측 날짜 패널 (월/주 공통)

    @ViewBuilder
    private var rightPanel: some View {
        if let day = selectedDay {
            panelResizeHandle
            CalendarDayPanel(
                day: day,
                store: store,
                boundary: boundary,
                onClose: { withAnimation(.easeInOut(duration: 0.18)) { selectedDay = nil } }
            )
            .frame(width: settings.calendarPanelWidth)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    /// 본문과 우측 패널 사이 경계 — 드래그로 패널 폭 조절(§12.2). 세터가 범위 클램프·영속을 보장한다.
    private var panelResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .overlay(Divider())
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = panelDragStartWidth ?? settings.calendarPanelWidth
                        if panelDragStartWidth == nil { panelDragStartWidth = start }
                        // 패널이 오른쪽에 있으므로 경계를 왼쪽으로 끌면(음수 translation) 폭이 커진다.
                        settings.calendarPanelWidth = start - Double(value.translation.width)
                    }
                    .onEnded { _ in panelDragStartWidth = nil }
            )
    }

    // MARK: - 액션

    private func select(_ day: Date) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedDay = (selectedDay == day) ? nil : day
        }
    }

    /// 드롭한 task의 scheduledDate를 대상 날짜로 변경 (v1 자정 날짜 키 규약: scheduledDateValue).
    private func reschedule(_ items: [CalendarTaskDrag], to day: Date) -> Bool {
        dropTargetDay = nil
        guard let item = items.first, let task = store.task(withID: item.taskID) else { return false }
        task.scheduledDate = boundary.scheduledDateValue(for: day)
        store.notifyChanged()
        return true
    }

    /// ◀/▶ — 현재 뷰 단위(달/주/일)로 이동한다 (§12.1).
    private func shift(_ delta: Int) {
        let base = anchorDate ?? boundary.logicalToday()
        withAnimation(.easeInOut(duration: 0.15)) {
            anchorDate = settings.calendarViewMode.shifted(base, by: delta, calendar: calendar)
        }
    }

    private func goToday() {
        let today = boundary.logicalToday()
        withAnimation(.easeInOut(duration: 0.18)) {
            anchorDate = today
            // 월/주 뷰에서는 오늘 날짜 패널을 함께 연다 (일간은 본문 자체가 오늘이 됨).
            if settings.calendarViewMode != .day {
                selectedDay = today
            }
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

/// 캘린더 → 사이드바 라우팅 (§21.6). 주간 목표 스트립 클릭 시 메인 창 사이드바 selection을
/// '주간 목표' 뷰로 바꾼다. selection은 MainWindowView가 소유하므로 알림으로 약결합 요청한다 —
/// 옵저버(MainWindowView)가 이 이름을 받아 selection = .weeklyGoals로 전환한다.
enum CalendarNavigation {
    static let selectWeeklyGoals = Notification.Name("AnhamDie.selectWeeklyGoals")

    @MainActor
    static func openWeeklyGoals() {
        NotificationCenter.default.post(name: selectWeeklyGoals, object: nil)
    }
}
