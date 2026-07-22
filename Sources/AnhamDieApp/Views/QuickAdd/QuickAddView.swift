import AppKit
import SwiftUI

/// 퀵애드 등록 페이로드. 컨트롤러가 스토어에 반영한다(태그 생성·lastUsedDueDate 갱신 포함).
struct QuickAddSubmission {
    var title: String
    var tagNames: [String]
    var priority: Priority?
    var date: QuickAddDateChoice
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
    @FocusState private var focused: Bool

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }
    private var settings: AppSettings { AppContext.shared.settings }

    private var parse: QuickAddParse {
        QuickAddTokenParser.parse(text, tags: store.tags, boundary: boundary)
    }

    /// 등록에 반영될 최종 날짜. 날짜 토큰이 있으면 그 값, 없고 백로그면 백로그, 그 외 미지정(기본 오늘).
    private var dateChoice: QuickAddDateChoice {
        if let d = parse.date { return .day(d.value) }
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
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 24, y: 12)
        .padding(24)
        .onExitCommand(perform: onCancel)
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
                if parse.tags.isEmpty && parse.priority == nil && chipDateIsEmpty {
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
            if let recent = settings.lastUsedDueDate {
                quickButton("최근: \(dateDisplay(for: recent))") { setDate(value: recent) }
            }
            quickButton("백로그", systemImage: "tray") { setBacklog() }
            Spacer(minLength: 0)
        }
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
        onCommit(
            QuickAddSubmission(
                title: p.title,
                tagNames: p.tags.map { $0.name },
                priority: p.priority,
                date: dateChoice
            ),
            keepOpen
        )
        if keepOpen {
            text = ""
            backlog = false
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
        rebuild(date: QuickAddDate(value: boundary.scheduledDateValue(for: day), display: display))
    }

    private func setDate(value: Date) {
        backlog = false
        rebuild(date: QuickAddDate(value: value, display: dateDisplay(for: value)))
    }

    private func setBacklog() {
        backlog = true
        rebuild(date: nil, clearDate: true)
    }

    private func clearDate() {
        backlog = false
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

    private func dateDisplay(for value: Date) -> String {
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
