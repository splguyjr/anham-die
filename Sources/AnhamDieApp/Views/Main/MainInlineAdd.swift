import Foundation

/// 메인 인라인 추가의 토큰 반영 (PLAN §11.8): QuickAddTokenParser 결과를 스토어에 태스크로 반영한다.
/// 태그 생성·우선순위·날짜 배정을 QuickAddController.commit과 같은 규약으로 처리한다.
@MainActor
enum MainInlineAdd {
    /// 신규 태그 순환 배정 색상 (QuickAddController와 동일 팔레트).
    private static let tagPalette = [
        "#FF6B6B", "#F59F00", "#FFD43B", "#51CF66", "#22B8CF",
        "#4C6EF5", "#7048E8", "#F06595", "#12B886", "#868E96"
    ]

    /// 파싱 결과로 태스크를 만들어 추가한다.
    /// - defaultScheduled: 날짜 토큰이 없을 때 쓸 scheduledDate (오늘 섹션=오늘, 백로그=nil).
    /// - extraTag: 태그 필터 뷰에서 추가로 부여할 태그 (없으면 nil).
    /// - 날짜 토큰이 있으면 그 날짜를 '자정 날짜 키'로 저장하고 lastUsedDueDate를 갱신한다(PLAN §10.7).
    static func commit(
        _ parse: QuickAddParse,
        defaultScheduled: Date?,
        extraTag: Tag?,
        store: TaskStore,
        boundary: DayBoundaryService,
        settings: AppSettings
    ) {
        let title = parse.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let scheduled: Date?
        if let tokenDate = parse.date {
            scheduled = boundary.scheduledDateValue(for: boundary.logicalDay(ofStored: tokenDate.value))
        } else {
            scheduled = defaultScheduled
        }

        var tagIDs = resolveTagIDs(parse.tags, store: store)
        if let extraTag, !tagIDs.contains(extraTag.id) {
            tagIDs.append(extraTag.id)
        }

        let task = TodoTask(
            title: title,
            scheduledDate: scheduled,
            priority: parse.priority ?? .normal,
            tagIDs: tagIDs
        )
        // 초기 배치는 스토어 단일 규칙(§11.3: 우선순위 → createdAt)으로 부여된다.
        store.addTaskApplyingInitialOrder(task)

        // 명시적으로 고른 날짜 토큰만 기억한다 (기본 오늘/백로그 제외) — 다음 등록의 [최근] 칩.
        if parse.date != nil, let scheduled {
            settings.lastUsedDueDate = scheduled
        }
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
