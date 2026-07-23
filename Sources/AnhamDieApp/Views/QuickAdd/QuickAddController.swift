import AppKit
import SwiftUI

/// 빠른 추가(⌥⌘N) 컨트롤러 — 어디서든 Spotlight식 입력창을 띄운다 (PLAN §3.4·§7).
/// nonactivating 패널이라 현재 앱 포커스를 뺏지 않으면서도 키 윈도우가 되어 입력을 받는다.
@MainActor
final class QuickAddController {
    static let shared = QuickAddController()

    private(set) var isVisible = false
    private var panel: QuickAddPanel?
    private var escMonitor: Any?

    func show() {
        let panel = ensurePanel()
        // 이미 떠 있으면 콘텐츠를 재설치하지 않는다 — 재설치는 새 NSHostingView(새 @State)라
        // ⌥⌘N 재입력만으로 작성 중 텍스트·선택이 사라진다. 포커스만 다시 준다.
        if !isVisible {
            installContent(in: panel)
            position(panel)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installEscMonitor()
        isVisible = true
    }

    func hide() {
        removeEscMonitor()
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: - 태스크 추가

    /// 신규 태그에 순환 배정하는 색상 팔레트 (설정 태그 탭에서 재편집 가능).
    private static let tagPalette = [
        "#FF6B6B", "#F59F00", "#FFD43B", "#51CF66", "#22B8CF",
        "#4C6EF5", "#7048E8", "#F06595", "#12B886", "#868E96"
    ]

    /// 입력 확정 처리. 제목이 있으면 파싱 결과(태그·우선순위·날짜)를 반영해 태스크를 추가한다.
    /// keepOpen이면 창을 유지(연속 입력), 아니면 닫는다.
    private func commit(_ submission: QuickAddSubmission, keepOpen: Bool) {
        let title = submission.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            let context = AppContext.shared
            let boundary = context.dayBoundary

            // scheduledDate 저장 규약: 항상 '자정 날짜 키'(scheduledDateValue). 미지정은 오늘(v1 규약).
            let scheduled: Date?
            switch submission.date {
            case .unspecified: scheduled = boundary.scheduledToday()
            case .backlog: scheduled = nil
            case .day(let day): scheduled = boundary.scheduledDateValue(for: boundary.logicalDay(ofStored: day))
            }

            let tagIDs = resolveTagIDs(submission.tagNames, store: context.store)
            let task = TodoTask(
                title: title,
                scheduledDate: scheduled,
                priority: submission.priority ?? .normal,
                tagIDs: tagIDs
            )
            // 초기 배치는 스토어 단일 규칙(§11.3: 우선순위 → createdAt)으로 부여된다.
            context.store.addTaskApplyingInitialOrder(task)

            // 명시적으로 고른 날짜만 기억한다(기본 오늘·백로그는 제외) — 다음 등록의 [최근] 칩 (PLAN §10.7).
            if case .day = submission.date, let scheduled {
                context.settings.lastUsedDueDate = scheduled
            }
        }
        if !keepOpen {
            hide()
        }
    }

    /// 태그 이름 목록을 태그 ID로 해석한다. 기존 태그는 대소문자 무시로 매칭, 없으면 생성한다.
    private func resolveTagIDs(_ names: [String], store: TaskStore) -> [UUID] {
        var ids: [UUID] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let existing = store.tags.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                if !ids.contains(existing.id) { ids.append(existing.id) }
            } else {
                let hex = Self.tagPalette[store.tags.count % Self.tagPalette.count]
                let tag = Tag(name: trimmed, colorHex: hex)
                store.addTag(tag)
                ids.append(tag.id)
            }
        }
        return ids
    }

    // MARK: - 패널 구성

    private func ensurePanel() -> QuickAddPanel {
        if let panel { return panel }
        let panel = QuickAddPanel()
        self.panel = panel
        return panel
    }

    private func installContent(in panel: QuickAddPanel) {
        let view = QuickAddView(
            onCommit: { [weak self] submission, keepOpen in
                self?.commit(submission, keepOpen: keepOpen)
            },
            onCancel: { [weak self] in
                self?.hide()
            }
        )
        let hosting = NSHostingView(rootView: view)
        var size = hosting.fittingSize
        if size.width < 1 || size.height < 1 {
            size = NSSize(width: 608, height: 240)
        }
        hosting.setFrameSize(size)
        panel.setContentSize(size)
        panel.contentView = hosting
    }

    private func position(_ panel: QuickAddPanel) {
        let screen = currentScreen()
        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        // Spotlight처럼 화면 상단 약 62% 높이에 중앙 정렬
        let y = screen.frame.minY + screen.frame.height * 0.62 - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func currentScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
            ?? NSScreen()
    }

    // MARK: - Esc 처리

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event } // 53 = Esc
            return MainActor.assumeIsolated {
                // 빠른 추가 패널로 향한 Esc만 소비한다 — 무조건 소비하면 브리핑 등 다른 키 윈도우에
                // 누른 Esc까지 가로채 그 창 대신 빠른 추가가 닫히는 문제가 있었다.
                guard let self, let panel = self.panel, event.window === panel else { return event }
                self.hide()
                return nil
            }
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }
}
