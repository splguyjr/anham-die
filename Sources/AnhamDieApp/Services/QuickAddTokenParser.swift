import Foundation

/// 퀵애드 v2 토큰 파싱 결과 (PLAN §10.8). 순수 값 타입 — 사이드이펙트 없음.
struct QuickAddParse: Equatable {
    /// 토큰(태그/우선순위/날짜)을 제거하고 트리밍한 제목
    var title: String
    /// 인식된 태그들 (입력 순서, 대소문자 무시 중복 제거)
    var tags: [QuickAddTag]
    /// 인식된 우선순위. 여러 개면 마지막 토큰이 이긴다. nil = 미지정
    var priority: Priority?
    /// 인식된 날짜. 여러 개면 마지막 토큰이 이긴다. nil = 미지정
    var date: QuickAddDate?
}

/// 파싱된 태그 하나. existingID가 있으면 스토어에 이미 있는 태그, 없으면 등록 시 생성 대상.
struct QuickAddTag: Equatable {
    var name: String
    var existingID: UUID?

    var isNew: Bool { existingID == nil }
}

/// 파싱된 날짜 하나. value는 '자정 날짜 키'(scheduledDateValue 규약),
/// display는 칩 표시 및 텍스트 토큰 재구성에 쓰는 정규 표기(오늘/내일/모레/M/d).
struct QuickAddDate: Equatable {
    var value: Date
    var display: String
}

/// #태그 · !우선순위 · 날짜 자연어를 실시간으로 파싱하는 순수 함수 모음 (PLAN §10.8).
/// 스토어·설정을 건드리지 않는다 — 태그 생성/lastUsedDueDate 갱신은 호출측(컨트롤러)의 몫.
enum QuickAddTokenParser {

    /// 입력 문자열을 파싱한다.
    /// - Parameters:
    ///   - raw: 사용자 입력 원문
    ///   - existingTags: 자동완성·기존 매칭에 쓰는 스토어의 현재 태그
    ///   - boundary: 날짜 자연어를 논리적 날짜로 변환하는 규약 소스
    static func parse(_ raw: String, tags existingTags: [Tag], boundary: DayBoundaryService) -> QuickAddParse {
        let calendar = boundary.calendar
        let today = boundary.logicalToday()
        let components = tokenize(raw)

        var titleWords: [String] = []
        var parsedTags: [QuickAddTag] = []
        var priority: Priority?
        var date: QuickAddDate?

        var index = 0
        while index < components.count {
            let comp = components[index]

            if comp.hasPrefix("#"), comp.count > 1 {
                appendTag(String(comp.dropFirst()), into: &parsedTags, existing: existingTags)
                index += 1
                continue
            }

            if comp.hasPrefix("!"), comp.count > 1,
               let parsed = parsePriority(fromKeyword: String(comp.dropFirst())) {
                priority = parsed
                index += 1
                continue
            }

            if let single = singleWordDate(comp, today: today, calendar: calendar) {
                date = single
                index += 1
                continue
            }

            if index + 1 < components.count,
               let paired = pairedMonthDay(components[index], components[index + 1], today: today, calendar: calendar) {
                date = paired
                index += 2
                continue
            }

            titleWords.append(comp)
            index += 1
        }

        let title = titleWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return QuickAddParse(title: title, tags: parsedTags, priority: priority, date: date)
    }

    // MARK: - 자동완성

    /// 지금 '작성 중'인 태그 조각. 마지막 토큰이 #로 시작하고 문자열이 공백으로 끝나지 않을 때만.
    /// 반환값이 ""이면 방금 #만 친 상태(전체 태그를 후보로 노출). nil이면 태그를 입력 중이 아님.
    static func activeTagFragment(in raw: String) -> String? {
        guard let last = raw.unicodeScalars.last,
              !CharacterSet.whitespacesAndNewlines.contains(last) else { return nil }
        guard let lastToken = raw.components(separatedBy: .whitespacesAndNewlines).last,
              lastToken.hasPrefix("#") else { return nil }
        return String(lastToken.dropFirst())
    }

    /// 조각에 부분일치하는 기존 태그 후보. prefix 일치를 앞에 배치하고, excluding에 든 이름은 뺀다.
    static func tagSuggestions(for fragment: String, in tags: [Tag], excluding: [String] = []) -> [Tag] {
        let needle = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        let excludedLower = Set(excluding.map { $0.lowercased() })
        let matches = tags.filter { tag in
            guard !excludedLower.contains(tag.name.lowercased()) else { return false }
            return needle.isEmpty || tag.name.range(of: needle, options: .caseInsensitive) != nil
        }
        return matches.sorted { a, b in
            let aPrefix = a.name.range(of: needle, options: [.caseInsensitive, .anchored]) != nil
            let bPrefix = b.name.range(of: needle, options: [.caseInsensitive, .anchored]) != nil
            if aPrefix != bPrefix { return aPrefix }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// 작성 중인 태그 조각을 고른 태그 이름으로 치환하고 뒤에 공백을 붙인다(다음 토큰 입력 준비).
    static func replacingActiveTagFragment(in raw: String, with tagName: String) -> String {
        guard activeTagFragment(in: raw) != nil,
              let hashRange = raw.range(of: "#", options: .backwards) else { return raw }
        return String(raw[..<hashRange.lowerBound]) + "#" + tagName + " "
    }

    // MARK: - 내부 헬퍼

    private static func tokenize(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
    }

    private static func appendTag(_ name: String, into tags: inout [QuickAddTag], existing: [Tag]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !tags.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        let match = existing.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        tags.append(QuickAddTag(name: match?.name ?? trimmed, existingID: match?.id))
    }

    private static func parsePriority(fromKeyword keyword: String) -> Priority? {
        switch keyword {
        case "높음", "1": return .high
        case "보통", "2": return .normal
        case "낮음", "3": return .low
        default: return nil
        }
    }

    private static func singleWordDate(_ comp: String, today: Date, calendar: Calendar) -> QuickAddDate? {
        switch comp {
        case "오늘":
            return QuickAddDate(value: calendar.startOfDay(for: today), display: "오늘")
        case "내일":
            let d = calendar.date(byAdding: .day, value: 1, to: today)!
            return QuickAddDate(value: calendar.startOfDay(for: d), display: "내일")
        case "모레":
            let d = calendar.date(byAdding: .day, value: 2, to: today)!
            return QuickAddDate(value: calendar.startOfDay(for: d), display: "모레")
        default:
            break
        }
        // "M/d"
        if comp.contains("/") {
            let parts = comp.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count == 2, let m = Int(parts[0]), let d = Int(parts[1]) {
                return monthDayDate(month: m, day: d, today: today, calendar: calendar)
            }
        }
        // "M월d일" (공백 없이 붙은 형태)
        if comp.hasSuffix("일"), comp.contains("월") {
            let body = comp.dropLast() // "일" 제거
            let parts = body.split(separator: "월", omittingEmptySubsequences: false)
            if parts.count == 2, let m = Int(parts[0]), let d = Int(parts[1]) {
                return monthDayDate(month: m, day: d, today: today, calendar: calendar)
            }
        }
        return nil
    }

    private static func pairedMonthDay(_ a: String, _ b: String, today: Date, calendar: Calendar) -> QuickAddDate? {
        guard a.hasSuffix("월"), b.hasSuffix("일"),
              let m = Int(a.dropLast()), let d = Int(b.dropLast()) else { return nil }
        return monthDayDate(month: m, day: d, today: today, calendar: calendar)
    }

    /// 월/일 → 올해(지났으면 내년) 그 날짜의 자정 날짜 키. 존재하지 않는 날짜는 nil(제목으로 남김).
    private static func monthDayDate(month: Int, day: Int, today: Date, calendar: Calendar) -> QuickAddDate? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let year = calendar.component(.year, from: today)

        func resolve(_ y: Int) -> Date? {
            var comps = DateComponents()
            comps.year = y
            comps.month = month
            comps.day = day
            guard let d = calendar.date(from: comps),
                  calendar.component(.month, from: d) == month,
                  calendar.component(.day, from: d) == day else { return nil }
            return calendar.startOfDay(for: d)
        }

        guard let thisYear = resolve(year) else { return nil }
        let value: Date
        if thisYear < calendar.startOfDay(for: today) {
            guard let nextYear = resolve(year + 1) else { return nil }
            value = nextYear
        } else {
            value = thisYear
        }
        return QuickAddDate(value: value, display: "\(month)/\(day)")
    }
}
