import AppKit
import SwiftUI

/// 포스트잇 카드 창 표시 계층 (v10 §19.1) — StickyNotePresenting 구현 싱글턴.
/// StickyNotesController가 모델·표시 정책을 정하고, 이 매니저가 노트별 창(StickyCardPanel)을
/// 만들고/앞으로/숨김 처리한다. 컨트롤러 init에서 attach로 연결된다(앱 시작 시 열림 노트 복원).
@MainActor
final class StickyCardManager: StickyNotePresenting {
    static let shared = StickyCardManager()

    /// 노트 id → 창 컨트롤러. 창은 노트마다 하나이며 present는 멱등(이미 있으면 앞으로만).
    private var controllers: [UUID: StickyCardWindowController] = [:]

    private init() {}

    func present(note: StickyNote, focus: Bool) {
        let controller: StickyCardWindowController
        if let existing = controllers[note.id] {
            controller = existing
        } else {
            controller = StickyCardWindowController(note: note)
            controllers[note.id] = controller
        }
        controller.present(focus: focus)
    }

    func dismiss(noteID: UUID) {
        controllers.removeValue(forKey: noteID)?.close()
    }

    func setAllVisible(_ visible: Bool) {
        for controller in controllers.values {
            controller.setVisible(visible)
        }
    }
}

/// 포스트잇 카드 창 한 개의 생명주기 (v10 §19.1).
/// 노트(참조 타입·@Observable)를 그대로 들고 프로퍼티를 직접 수정한 뒤 stickies.notifyChanged()로
/// 영속화를 트리거한다. frame 저장은 드래그/리사이즈 종료 시 1회(§19.4 에너지 규약).
@MainActor
final class StickyCardWindowController: NSObject, NSWindowDelegate {
    private let note: StickyNote
    private let panel: StickyCardPanel
    private var stickies: StickyStore { AppContext.shared.stickies }
    /// 사용자가 본문을 한 번이라도 편집했는지 (§21.5) — 무편집·빈 노트 닫기는 아카이브 않고 폐기한다.
    private var edited = false

    init(note: StickyNote) {
        self.note = note
        panel = StickyCardPanel(contentRect: Self.sanitizedFrame(note.frame))
        super.init()
        panel.delegate = self
        panel.applyPinned(note.pinned)

        let view = StickyCardView(
            note: note,
            onTogglePin: { [weak self] in self?.togglePin() },
            onAddNote: { [weak self] in self?.addNote() },
            onClose: { [weak self] in self?.closeNote() },
            onDragEnded: { [weak self] in self?.commitFrame() },
            onEdited: { [weak self] in self?.edited = true }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]
        // 콘텐츠가 창 크기를 강제하지 않도록(자유 리사이즈 방해 방지) 크기 옵션을 비운다.
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.invalidateShadow()
    }

    // MARK: - 표시

    func present(focus: Bool) {
        panel.applyPinned(note.pinned)
        if focus {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            focusEditor()
        } else {
            panel.orderFrontRegardless()
        }
    }

    func setVisible(_ visible: Bool) {
        if visible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    /// 닫기(X) 처리 (§19.2·§21.5). 본문이 공백(trim 후 빈)이고 한 번도 편집되지 않았으면
    /// 아카이브하지 않고 폐기한다(stickies.json에 남기지 않음). 그 외에는 기존대로 아카이브.
    /// 두 경로 모두 presenter.dismiss로 이어져 매니저가 이 컨트롤러를 제거·close 한다.
    private func closeNote() {
        let empty = note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty && !edited {
            StickyNotesController.shared.discard(note: note)
        } else {
            StickyNotesController.shared.archive(note: note)
        }
    }

    /// 창을 화면에서 내리고 파괴한다 (매니저의 dismiss 경로).
    func close() {
        panel.orderOut(nil)
        panel.delegate = nil
        panel.contentView = nil
        panel.close()
    }

    // MARK: - 액션

    private func togglePin() {
        note.pinned.toggle()
        panel.applyPinned(note.pinned)
        stickies.notifyChanged()
    }

    private func addNote() {
        // + 버튼 — 현재 카드 원점 근처에 어긋나게 새 노트 (§19.1).
        StickyNotesController.shared.createNote(near: panel.frame.origin)
    }

    // MARK: - frame 저장 (드래그/리사이즈 종료 시 1회 · §19.4)

    private func commitFrame() {
        note.frame = panel.frame
        stickies.notifyChanged()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        commitFrame()
        panel.invalidateShadow()
    }

    // MARK: - 포커스

    /// 본문 TextEditor의 NSTextView를 첫 응답자로 만들어 즉시 입력을 받게 한다.
    /// 호스팅 뷰 레이아웃 이후여야 하므로 다음 런루프로 미룬다.
    private func focusEditor() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let content = self.panel.contentView,
                  let textView = Self.firstTextView(in: content) else { return }
            self.panel.makeFirstResponder(textView)
        }
    }

    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }

    // MARK: - frame 정합

    /// 저장된 frame을 하한/상한 크기와 현재 화면 안으로 보정한다 — 모니터 구성이 바뀌어
    /// 완전히 화면 밖이 된 노트가 잡히지 않는 것을 막는다.
    static func sanitizedFrame(_ frame: CGRect) -> CGRect {
        var size = frame.size
        size.width = min(max(size.width, StickyCardMetrics.minSize.width), StickyCardMetrics.maxSize.width)
        size.height = min(max(size.height, StickyCardMetrics.minSize.height), StickyCardMetrics.maxSize.height)
        var origin = frame.origin
        let screen = NSScreen.screens.first { $0.frame.intersects(CGRect(origin: origin, size: size)) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
            origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        }
        return CGRect(origin: origin, size: size)
    }
}
