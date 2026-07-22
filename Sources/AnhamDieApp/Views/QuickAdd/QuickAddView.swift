import AppKit
import SwiftUI

/// Spotlight식 빠른 추가 입력 카드 (PLAN §7).
/// - Enter: 오늘에 추가 후 닫기
/// - Shift+Enter: 오늘에 추가하고 창 유지(연속 입력)
/// - Esc: 닫기 (컨트롤러의 로컬 모니터가 우선 처리, 여기 onExitCommand는 폴백)
struct QuickAddView: View {
    /// (제목, 연속입력 유지 여부). 태스크 추가 및 닫기 여부는 컨트롤러가 결정한다.
    let onCommit: (String, Bool) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.secondary)
                TextField("오늘 할 일 빠른 추가", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .regular))
                    .focused($focused)
                    .onSubmit(submit)
            }
            HStack(spacing: 14) {
                hint("Enter", "오늘에 추가")
                hint("⇧Enter", "연속 추가")
                Spacer(minLength: 0)
                hint("Esc", "닫기")
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
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

    private func submit() {
        let keepOpen = NSEvent.modifierFlags.contains(.shift)
        onCommit(text, keepOpen)
        if keepOpen {
            text = ""
            focused = true
        }
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
