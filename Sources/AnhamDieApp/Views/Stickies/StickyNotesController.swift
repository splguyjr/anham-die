import AppKit

/// 노트 카드 창 표시 계층의 계약 (v10 §19.1) — 카드 UI 모듈이 구현해 attach(presenter:)로 연결한다.
/// 컨트롤러는 모델·표시 정책(무엇을/언제)을 결정하고, 창 자체(NSPanel 생성·레벨·포커스)는
/// 프리젠터가 담당한다. 창 규약: 기본은 일반 창 레벨, 핀 시에만 floating+canJoinAllSpaces+
/// fullScreenAuxiliary. 위치 저장은 드래그 종료 시 1회 → note.frame 갱신 + store.notifyChanged().
@MainActor
protocol StickyNotePresenting: AnyObject {
    /// 노트 카드 창을 만들거나 앞으로 가져온다. focus=true면 텍스트 에디터에 즉시 입력 포커스.
    func present(note: StickyNote, focus: Bool)
    /// 노트 카드 창을 화면에서 제거한다 (보관 시 — 창 파괴 또는 orderOut은 구현 재량).
    func dismiss(noteID: UUID)
    /// 이미 만들어진 열린 카드 전체를 표시/숨김 (⌥⌘H 토글 경로 — 창 파괴 없이 order in/out).
    func setAllVisible(_ visible: Bool)
}

/// 포스트잇 창 생명주기의 단일 진입점 (v10 §19.1·§19.3 — 싱글턴).
/// 단축키(⌥⌘S/⌥⌘H)·메뉴바 버튼·보관함 뷰가 모두 이 컨트롤러를 호출한다.
/// 카드 UI 모듈이 attach(presenter:)를 호출하기 전까지는 모델 변경만 수행하는 스텁으로 동작한다.
@MainActor
final class StickyNotesController {
    static let shared = StickyNotesController()

    private var stickies: StickyStore { AppContext.shared.stickies }
    /// 열린 노트 전체 표시 상태 (⌥⌘H 토글) — 세션 내 상태. 노트 생성/열기는 항상 표시로 되돌린다.
    private(set) var allVisible = true
    /// 카드 UI 모듈의 프리젠터 (싱글턴 매니저 전제 — attach 이후 앱 상주 내내 유지).
    private var presenter: StickyNotePresenting?

    private init() {
        // 카드 UI 프리젠터 자동 연결 (§19.1) — App.swift의 `_ = StickyNotesController.shared`가
        // 앱 시작 시 이 init을 트리거하고, attach가 열림 노트 카드 복원 표시까지 수행한다.
        // (외부에서 attach(presenter:)를 다시 호출해도 present가 멱등이라 창이 중복 생성되지 않는다.)
        attach(presenter: StickyCardManager.shared)
    }

    /// 카드 UI 모듈이 시작 시 1회 호출 — 열린 노트들의 카드 창 복원 표시까지 수행한다.
    func attach(presenter: StickyNotePresenting) {
        self.presenter = presenter
        guard allVisible else { return }
        for note in stickies.openNotes {
            presenter.present(note: note, focus: false)
        }
    }

    // MARK: - 표시/숨김 (⌥⌘H)

    func showAll() {
        allVisible = true
        presenter?.setAllVisible(true)
        // 숨김 중 다시 연 노트 등 아직 창이 없는 열린 노트도 마저 만든다.
        for note in stickies.openNotes {
            presenter?.present(note: note, focus: false)
        }
    }

    func hideAll() {
        allVisible = false
        presenter?.setAllVisible(false)
    }

    func toggleAllVisible() {
        allVisible ? hideAll() : showAll()
    }

    // MARK: - 생성/열기/보관

    /// 새 노트 생성 (⌥⌘S·+ 버튼) — 기준점(커서 또는 기존 노트) 근처에 살짝 어긋나게 배치하고
    /// 즉시 입력 포커스를 준다 (§19.1). reference가 nil이면 현재 마우스 위치를 쓴다.
    @discardableResult
    func createNote(near reference: CGPoint? = nil) -> StickyNote {
        let note = StickyNote(frame: cascadedFrame(near: reference ?? NSEvent.mouseLocation))
        stickies.add(note)
        allVisible = true
        presenter?.present(note: note, focus: true)
        return note
    }

    /// 노트 카드를 표시/포커스한다. 보관된 노트면 다시 열어(§19.2 다시 열기) 표시한다.
    func open(note: StickyNote) {
        if !note.isOpen {
            stickies.reopen(note)
        }
        allVisible = true
        presenter?.present(note: note, focus: true)
    }

    /// 카드 닫기 = 보관 (§19.2) — 창을 내리고 노트를 보관함으로 보낸다.
    func archive(note: StickyNote) {
        stickies.archive(note)
        presenter?.dismiss(noteID: note.id)
    }

    // MARK: - 배치

    /// 기준점 아래-오른쪽으로 어긋난 새 카드 프레임. 기존 열린 노트와 원점이 겹치면
    /// 계단식으로 더 밀고, 마지막에 기준점이 속한 화면 안으로 클램프한다.
    private func cascadedFrame(near anchor: CGPoint) -> CGRect {
        let size = StickyNote.defaultSize
        let step: CGFloat = 24
        var origin = CGPoint(x: anchor.x + 18, y: anchor.y - size.height - 18)
        var attempts = 0
        while attempts < 20, stickies.openNotes.contains(where: { note in
            abs(note.frame.origin.x - origin.x) < 4 && abs(note.frame.origin.y - origin.y) < 4
        }) {
            origin.x += step
            origin.y -= step
            attempts += 1
        }
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
            origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        }
        return CGRect(origin: origin, size: size)
    }
}
