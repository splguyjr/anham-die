import Foundation

/// '언젠가' 인라인 추가의 토큰 반영 (PLAN §22.2). MainInlineAdd와 같은 규약이되
/// '언젠가'는 의도적으로 날짜 없음(§22.1)이라 날짜 토큰은 무시하고 bucket=someday로 고정한다.
@MainActor
enum SomedayInlineAdd {
    // 신규 태그 순환 배정 색상 — MainInlineAdd·QuickAddController와 동일 팔레트.
    private static let tagPalette = [
        "#FF6B6B", "#F59F00", "#FFD43B", "#51CF66", "#22B8CF",
        "#4C6EF5", "#7048E8", "#F06595", "#12B886", "#868E96"
    ]

    /// 파싱 결과로 '언젠가' 태스크(bucket=someday·일정 nil)를 만들어 추가한다.
    /// #태그·!우선순위만 반영하고 날짜 토큰은 무시한다(§22.1 — '언젠가'는 due 없음).
    static func commit(_ parse: QuickAddParse, store: TaskStore) {
        let title = parse.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let tagIDs = resolveTagIDs(parse.tags, store: store)
        let task = TodoTask(
            title: title,
            priority: parse.priority ?? .normal,
            tagIDs: tagIDs,
            bucket: .someday
        )
        // 초기 배치는 스토어 단일 규칙(§11.3)으로 부여된다.
        store.addTaskApplyingInitialOrder(task)
    }

    /// 파싱된 태그를 태그 ID로 해석한다. 기존은 매칭, 신규는 팔레트 색으로 생성.
    private static func resolveTagIDs(_ tags: [QuickAddTag], store: TaskStore) -> [UUID] {
        var ids: [UUID] = []
        for tag in tags {
            if let existingID = tag.existingID {
                if !ids.contains(existingID) { ids.append(existingID) }
                continue
            }
            let trimmed = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let existing = store.tags.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                if !ids.contains(existing.id) { ids.append(existing.id) }
            } else {
                let hex = tagPalette[store.tags.count % tagPalette.count]
                let created = Tag(name: trimmed, colorHex: hex)
                store.addTag(created)
                ids.append(created.id)
            }
        }
        return ids
    }
}
