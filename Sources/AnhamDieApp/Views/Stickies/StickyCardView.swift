import AppKit
import SwiftUI

/// 포스트잇 카드 본문 (v10 §19.1) — 상단 바(핀·색상 메뉴·새 노트·닫기) + 멀티라인 본문 에디터.
/// 색은 note.colorID의 fill/ink/barTint(데이터 정체성, 테마 무관 — §19.1 모노 예외)를 쓴다.
/// 텍스트·색 변경은 note를 직접 수정 후 stickies.notifyChanged()(0.5s 디바운스)로 저장한다.
/// 창을 건드리는 동작(핀 레벨·이동 frame 저장·새 노트·닫기=아카이브)만 컨트롤러 클로저로 위임한다.
struct StickyCardView: View {
    @Bindable var note: StickyNote
    let onTogglePin: () -> Void
    let onAddNote: () -> Void
    let onClose: () -> Void
    let onDragEnded: () -> Void

    private var stickies: StickyStore { AppContext.shared.stickies }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            editor
        }
        .background(note.colorID.fill)
        .clipShape(RoundedRectangle(cornerRadius: StickyCardMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StickyCardMetrics.cornerRadius, style: .continuous)
                .strokeBorder(note.colorID.ink.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - 상단 바

    private var topBar: some View {
        HStack(spacing: 6) {
            pinButton
            colorMenu
            // 가운데 빈 영역이 창 이동 드래그 존 — 버튼은 각자 클릭을 소비한다.
            StickyCardDragRegion(onDragEnded: onDragEnded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            barButton(system: "plus", help: "새 포스트잇", action: onAddNote)
            barButton(system: "xmark", help: "닫기(보관함으로)", action: onClose)
        }
        .padding(.horizontal, 6)
        .frame(height: StickyCardMetrics.barHeight)
        .background(note.colorID.barTint)
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: note.pinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(note.colorID.ink.opacity(note.pinned ? 1.0 : 0.55))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(note.pinned ? "핀 해제" : "항상 위로 핀")
    }

    private var colorMenu: some View {
        Menu {
            ForEach(StickyColorID.allCases, id: \.self) { color in
                Button {
                    note.colorID = color
                    stickies.notifyChanged()
                } label: {
                    HStack {
                        Circle().fill(color.fill).frame(width: 12, height: 12)
                        Text(color.displayName)
                        if color == note.colorID {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Circle()
                .fill(note.colorID.fill)
                .overlay(Circle().strokeBorder(note.colorID.ink.opacity(0.45), lineWidth: 1))
                .frame(width: 13, height: 13)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 20, height: 18)
        .help("색상 바꾸기")
    }

    private func barButton(system: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(note.colorID.ink.opacity(0.6))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 본문

    private var editor: some View {
        TextEditor(text: $note.text)
            .font(.system(size: 14))
            .foregroundStyle(note.colorID.ink)
            .tint(note.colorID.ink)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(note.colorID.fill)
            .overlay(alignment: .topLeading) {
                if note.text.isEmpty {
                    Text("메모…")
                        .font(.system(size: 14))
                        .foregroundStyle(note.colorID.ink.opacity(0.35))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: note.text) {
                // 키 입력마다 호출되지만 영속화는 0.5s 트레일링 디바운스로 1회만 (§19.4).
                stickies.notifyChanged()
            }
    }
}

/// 상단 바 가운데의 창 이동 드래그 존 (v10 §19.1). 화면 좌표 델타로 패널 origin을 옮기고
/// (이동 중 좌표계 흔들림 방지), 드래그 종료(mouseUp) 시 1회만 frame 저장을 트리거한다 —
/// 오버레이 헤더 드래그와 같은 에너지 규약(§19.4). 이동이 아니면(단순 클릭) 아무것도 하지 않는다.
private struct StickyCardDragRegion: NSViewRepresentable {
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.onDragEnded = onDragEnded
    }

    final class DragView: NSView {
        var onDragEnded: () -> Void = {}
        private var dragged = false
        private var lastScreen: NSPoint = .zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            dragged = false
            lastScreen = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let now = NSEvent.mouseLocation
            let dx = now.x - lastScreen.x
            let dy = now.y - lastScreen.y
            if !dragged && hypot(dx, dy) < 3 { return }
            dragged = true
            var origin = window.frame.origin
            origin.x += dx
            origin.y += dy
            window.setFrameOrigin(origin)
            lastScreen = now
        }

        override func mouseUp(with event: NSEvent) {
            if dragged {
                // 드래그 종료 시 최종 frame을 1회만 저장한다 (드래그 중 저장 방지 · §19.4).
                onDragEnded()
            }
        }
    }
}
