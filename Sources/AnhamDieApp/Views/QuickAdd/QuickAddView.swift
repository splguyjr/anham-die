import AppKit
import SwiftUI

/// 퀵애드 등록 페이로드. 컨트롤러가 스토어에 반영한다(태그 생성·lastUsedDueDate 갱신 포함).
struct QuickAddSubmission {
    var title: String
    var tagNames: [String]
    var priority: Priority?
    var date: QuickAddDateChoice
    /// 반복 규칙 (PLAN §11.5). 칩 선택 UI로만 지정 — 토큰 파싱은 하지 않는다.
    var recurrence: RecurrenceRule = .none
}

/// 퀵애드에서 고른 날짜의 의미. '미지정(기본 오늘)'과 '백로그(날짜 없음)'를 구분한다.
enum QuickAddDateChoice: Equatable {
    case unspecified   // 날짜 토큰 없음 → 오늘에 추가(v1 규약), lastUsedDueDate 갱신 안 함
    case backlog       // 백로그 → scheduledDate 없음
    case day(Date)     // 그 날짜에 예정 → lastUsedDueDate 갱신
}

/// Spotlight식 빠른 추가 입력 카드 v2 (PLAN §7·§10.8).
/// - 입력 중 실시간 토큰 파싱(#태그·!우선순위·날짜) → 아래 칩 행에 반영
/// - Enter: 토큰 제거된 제목으로 등록 후 닫기 · Shift+Enter: 등록 후 창 유지 · Esc: 닫기
struct QuickAddView: View {
    let onCommit: (QuickAddSubmission, Bool) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    /// 백로그 명시 선택 여부. 날짜 토큰이 입력되면 무시된다(토큰 우선).
    @State private var backlog: Bool = false
    /// 버튼으로 명시 선택한 날짜의 원값. 텍스트의 M/d 토큰은 연도를 담지 못해
    /// 과거 날짜가 재파싱 시 내년으로 밀리므로, 표기가 같은 동안은 이 값을 우선한다.
    @State private var pinnedDate: QuickAddDate?
    /// 토큰만 있고 제목이 빈 채 Enter를 누른 상태 — 등록하지 않고 패널을 유지하며 피드백만 준다.
    /// (그냥 닫으면 '#태그 내일' 같은 입력이 무피드백으로 소실된다.)
    @State private var titleMissing = false
    /// 반복 규칙 — 칩/메뉴로만 지정(토큰 파싱 없음, PLAN §11.5). 텍스트와 무관한 순수 상태.
    @State private var recurrence: RecurrenceRule = .none
    @FocusState private var focused: Bool

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }
    private var settings: AppSettings { AppContext.shared.settings }

    private var parse: QuickAddParse {
        QuickAddTokenParser.parse(text, tags: store.tags, boundary: boundary)
    }

    /// 등록에 반영될 최종 날짜. 날짜 토큰이 있으면 그 값, 없고 백로그면 백로그, 그 외 미지정(기본 오늘).
    /// 버튼으로 고른 날짜(pinnedDate)는 토큰 표기가 유지되는 동안 재파싱 값보다 우선한다
    /// — 재파싱은 과거 M/d를 내년으로 해석해 원값을 잃는다.
    private var dateChoice: QuickAddDateChoice {
        if let d = parse.date {
            if let pinned = pinnedDate, pinned.display == d.display { return .day(pinned.value) }
            return .day(d.value)
        }
        if backlog { return .backlog }
        return .unspecified
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputRow
            chipRow
            quickActionRow
            assistRow
            hintRow
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 560)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    titleMissing ? Color.red.opacity(0.55) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 24, y: 12)
        .padding(24)
        .onExitCommand(perform: onCancel)
        .onChange(of: text) {
            titleMissing = false
            // 사용자가 날짜 토큰을 지우거나 바꾸면 버튼 고정값을 버리고 입력 그대로 해석한다.
            if let pinned = pinnedDate, parse.date?.display != pinned.display {
                pinnedDate = nil
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }

    // MARK: - 입력 행

    private var inputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
            TextField("할 일 입력  ·  #태그 !높음 내일", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .focused($focused)
                .onSubmit(submit)
        }
    }

    // MARK: - 칩 행 (파싱 결과 실시간 표시, 클릭 수정)

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(parse.tags, id: \.name) { tag in
                    tagChip(tag)
                }
                if let priority = parse.priority {
                    priorityChip(priority)
                }
                dateChipView
                if recurrence != .none {
                    recurrenceChip
                }
                if parse.tags.isEmpty && parse.priority == nil && chipDateIsEmpty && recurrence == .none {
                    Text("입력하면 태그·우선순위·날짜가 여기 표시됩니다")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 1)
        }
        .frame(height: 26)
    }

    private var chipDateIsEmpty: Bool {
        if case .unspecified = dateChoice { return true }
        return false
    }

    private func tagChip(_ tag: QuickAddTag) -> some View {
        let color = tag.existingID.flatMap { id in store.tags.first { $0.id == id } }
            .map { AppTheme.tagColor($0.colorHex) } ?? Color.secondary
        return chip(background: color.opacity(0.16), stroke: color.opacity(0.5)) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(tag.name).font(.system(size: 12, weight: .medium))
            if tag.isNew {
                Text("신규").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            removeButton { removeTag(tag.name) }
        }
    }

    private func priorityChip(_ priority: Priority) -> some View {
        let color = AppTheme.priorityColor(priority)
        return Menu {
            ForEach(Priority.allCases.reversed(), id: \.self) { p in
                Button(p.displayName) { setPriority(p) }
            }
            Divider()
            Button("우선순위 지우기") { clearPriority() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(color)
                Text(priority.displayName).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.16)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var dateChipView: some View {
        switch dateChoice {
        case .day(let value):
            chip(background: AppTheme.accent.opacity(0.16), stroke: AppTheme.accent.opacity(0.5)) {
                Image(systemName: "calendar").font(.system(size: 10)).foregroundStyle(AppTheme.accent)
                Text(dateDisplay(for: value)).font(.system(size: 12, weight: .medium))
                removeButton { clearDate() }
            }
        case .backlog:
            chip(background: Color.secondary.opacity(0.14), stroke: Color.secondary.opacity(0.4)) {
                Image(systemName: "tray").font(.system(size: 10)).foregroundStyle(.secondary)
                Text("백로그").font(.system(size: 12, weight: .medium))
                removeButton { clearDate() }
            }
        case .unspecified:
            EmptyView()
        }
    }

    // MARK: - 빠른 버튼 행 (오늘/내일/최근/백로그)

    private var quickActionRow: some View {
        HStack(spacing: 8) {
            quickButton("오늘") { setDate(relativeDays: 0, display: "오늘") }
            quickButton("내일") { setDate(relativeDays: 1, display: "내일") }
            if let recent = recentDate {
                quickButton("최근: \(dateDisplay(for: recent))") { setDate(value: recent) }
            }
            quickButton("백로그", systemImage: "tray") { setBacklog() }
            recurrenceMenuButton
            Spacer(minLength: 0)
        }
    }

    /// 반복 규칙 선택 진입 버튼 (Menu). 선택 시 chipRow에 반복 칩이 나타난다.
    private var recurrenceMenuButton: some View {
        Menu {
            recurrenceMenuContent
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
                Text(recurrence == .none ? "반복" : recurrence.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(
                recurrence == .none ? Color.primary.opacity(0.07) : AppTheme.accent.opacity(0.14)
            ))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// 반복 칩 (chipRow) — recurrence != .none일 때만. 칩 자체가 재선택 Menu이자 제거 버튼을 갖는다.
    private var recurrenceChip: some View {
        let color = AppTheme.accent
        return HStack(spacing: 5) {
            Menu {
                recurrenceMenuContent
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10)).foregroundStyle(color)
                    Text(recurrence.displayName).font(.system(size: 12, weight: .medium))
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            removeButton { recurrence = .none }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.16)))
        .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
    }

    /// 반복 규칙 메뉴 항목 (버튼/칩 공용). 매주는 요일별 토글 서브메뉴.
    @ViewBuilder
    private var recurrenceMenuContent: some View {
        Button("반복 안 함") { recurrence = .none }
        Button("매일") { recurrence = .daily }
        Button("평일 (월~금)") { recurrence = .weekdays }
        Menu("매주 (요일 선택)") {
            // 1=일 … 7=토 (Calendar.weekday 규약, PLAN §11.5)
            ForEach(1...7, id: \.self) { weekday in
                Button {
                    toggleWeeklyDay(weekday)
                } label: {
                    Text((weeklyContains(weekday) ? "✓ " : "") + weekdaySymbol(weekday))
                }
            }
        }
    }

    private func weekdaySymbol(_ weekday: Int) -> String {
        ["일", "월", "화", "수", "목", "금", "토"][weekday - 1]
    }

    private func weeklyContains(_ weekday: Int) -> Bool {
        if case .weekly(let days) = recurrence { return days.contains(weekday) }
        return false
    }

    /// 매주 규칙에서 해당 요일을 토글한다. 남는 요일이 없으면 반복 없음으로 되돌린다.
    private func toggleWeeklyDay(_ weekday: Int) {
        var days: Set<Int> = { if case .weekly(let d) = recurrence { return d } else { return [] } }()
        if days.contains(weekday) { days.remove(weekday) } else { days.insert(weekday) }
        recurrence = days.isEmpty ? .none : .weekly(days)
    }

    /// [최근] 버튼에 노출할 날짜 — 오늘/내일 버튼과 겹치면 중복이라 숨긴다 (DueDateControls.recentDate와 동일 규칙).
    private var recentDate: Date? {
        guard let recent = settings.lastUsedDueDate else { return nil }
        let key = boundary.scheduledDateValue(for: recent)
        let today = boundary.logicalToday()
        if key == boundary.scheduledDateValue(for: today) { return nil }
        let tomorrow = boundary.calendar.date(byAdding: .day, value: 1, to: today)!
        if key == boundary.scheduledDateValue(for: tomorrow) { return nil }
        return key
    }

    // MARK: - 보조 행 (태그 자동완성 후보 또는 문법 힌트)

    @ViewBuilder
    private var assistRow: some View {
        if let fragment = QuickAddTokenParser.activeTagFragment(in: text) {
            let already = parse.tags.map { $0.name }
            let suggestions = QuickAddTokenParser.tagSuggestions(for: fragment, in: store.tags, excluding: already)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(suggestions) { tag in
                        Button { completeTag(tag.name) } label: {
                            HStack(spacing: 5) {
                                Circle().fill(AppTheme.tagColor(tag.colorHex)).frame(width: 7, height: 7)
                                Text(tag.name).font(.system(size: 12))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                    if !fragment.isEmpty && !suggestions.contains(where: { $0.name.caseInsensitiveCompare(fragment) == .orderedSame }) {
                        Text("↵로 새 태그 ‘\(fragment)’ 생성")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(height: 24)
        } else {
            Text("#태그 · !높음/!낮음(!1~!3) · 오늘·내일·모레·M/d")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(height: 24, alignment: .leading)
        }
    }

    // MARK: - 키 힌트 행

    private var hintRow: some View {
        HStack(spacing: 14) {
            if titleMissing {
                Text("제목을 입력해야 등록됩니다")
                    .foregroundStyle(.red)
            }
            hint("Enter", "등록")
            hint("⇧Enter", "연속 등록")
            Spacer(minLength: 0)
            hint("Esc", "닫기")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }

    // MARK: - 제출

    private func submit() {
        let keepOpen = NSEvent.modifierFlags.contains(.shift)
        let p = parse
        guard !p.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            titleMissing = true
            return
        }
        onCommit(
            QuickAddSubmission(
                title: p.title,
                tagNames: p.tags.map { $0.name },
                priority: p.priority,
                date: dateChoice,
                recurrence: recurrence
            ),
            keepOpen
        )
        if keepOpen {
            text = ""
            backlog = false
            pinnedDate = nil
            recurrence = .none
            focused = true
        }
    }

    // MARK: - 칩/버튼 편집 (텍스트를 정규 표기로 재구성)

    private func removeTag(_ name: String) {
        let remaining = parse.tags.map { $0.name }.filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        rebuild(tags: remaining)
    }

    private func setPriority(_ priority: Priority) { rebuild(priority: priority) }
    private func clearPriority() { rebuild(priority: nil, clearPriority: true) }

    private func setDate(relativeDays: Int, display: String) {
        let day = boundary.calendar.date(byAdding: .day, value: relativeDays, to: boundary.logicalToday())!
        backlog = false
        pinnedDate = nil
        rebuild(date: QuickAddDate(value: boundary.scheduledDateValue(for: day), display: display))
    }

    private func setDate(value: Date) {
        backlog = false
        let date = QuickAddDate(value: value, display: tokenDisplay(for: value))
        pinnedDate = date
        rebuild(date: date)
    }

    private func setBacklog() {
        backlog = true
        pinnedDate = nil
        rebuild(date: nil, clearDate: true)
    }

    private func clearDate() {
        backlog = false
        pinnedDate = nil
        rebuild(date: nil, clearDate: true)
    }

    private func completeTag(_ name: String) {
        text = QuickAddTokenParser.replacingActiveTagFragment(in: text, with: name)
        focused = true
    }

    /// 현재 파싱 상태에서 일부 요소만 바꿔 텍스트를 정규 표기("제목 날짜 !우선순위 #태그")로 재작성한다.
    private func rebuild(
        tags newTags: [String]? = nil,
        priority newPriority: Priority? = nil,
        clearPriority: Bool = false,
        date newDate: QuickAddDate? = nil,
        clearDate: Bool = false
    ) {
        let p = parse
        let tags = newTags ?? p.tags.map { $0.name }
        let priority: Priority? = clearPriority ? nil : (newPriority ?? p.priority)
        let date: QuickAddDate? = clearDate ? nil : (newDate ?? p.date)

        var parts: [String] = []
        let title = p.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { parts.append(title) }
        if let date { parts.append(date.display) }
        if let priority { parts.append("!" + priorityWord(priority)) }
        for tag in tags { parts.append("#" + tag) }
        text = parts.joined(separator: " ")
        focused = true
    }

    // MARK: - 표기 헬퍼

    private func priorityWord(_ p: Priority) -> String {
        switch p {
        case .high: return "높음"
        case .normal: return "보통"
        case .low: return "낮음"
        }
    }

    /// 텍스트 토큰용 정규 표기 — 파서가 그대로 되읽는 형태라 연도를 담지 않는다(pinnedDate가 원값 보존).
    private func tokenDisplay(for value: Date) -> String {
        let day = boundary.logicalDay(ofStored: value)
        let today = boundary.logicalToday()
        let cal = boundary.calendar
        if day == today { return "오늘" }
        if day == cal.date(byAdding: .day, value: 1, to: today) { return "내일" }
        if day == cal.date(byAdding: .day, value: 2, to: today) { return "모레" }
        let m = cal.component(.month, from: day)
        let d = cal.component(.day, from: day)
        return "\(m)/\(d)"
    }

    /// 칩·버튼 라벨용 표기. 올해가 아니면 연도를 붙인다 — '지났으면 내년' 해석으로
    /// 1년 뒤에 등록되는 날짜를 사용자가 표기만 보고도 알 수 있게.
    private func dateDisplay(for value: Date) -> String {
        let base = tokenDisplay(for: value)
        let cal = boundary.calendar
        let y = cal.component(.year, from: boundary.logicalDay(ofStored: value))
        if y != cal.component(.year, from: boundary.logicalToday()), base.contains("/") {
            return "\(y)년 \(base)"
        }
        return base
    }

    // MARK: - 작은 조각

    private func chip<Content: View>(
        background: Color,
        stroke: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 5) { content() }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func quickButton(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10))
                }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                )
            Text(label)
        }
    }
}
