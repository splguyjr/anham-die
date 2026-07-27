import SwiftUI

/// v7 커스텀 테마 편집기 (PLAN §15.1) — 선택된 커스텀 테마의 12색 슬롯·이름·isDark를 실시간 편집한다.
///
/// 소스 오브 트루스는 `AppSettings.customThemes`이며, 모든 편집은 값을 복사해 수정 후
/// `ThemeManager.updateCustomTheme(_:)`로 되돌려 쓴다 → @Observable 경유로 전 화면이 즉시 재평가된다.
/// 바인딩 setter는 항상 매니저에서 id로 최신 값을 다시 읽어 수정하므로, 연속 편집 중 스테일 스냅샷이
/// 이전 변경을 덮어쓰지 않는다(예: 색 A 변경 직후 색 B 변경). 슬롯 ↺ 리셋은 baseThemeID 프리셋 값.
struct ThemeEditorView: View {
    let themeID: UUID

    private var manager: ThemeManager { AppContext.shared.theme }

    /// 슬롯 ColorPicker 그리드 — 설정 창 폭(약 440pt 가용)에서 2열로 배치된다.
    private let slotColumns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 10)]

    var body: some View {
        // customThemes 읽기로 관찰 등록 + 최신 값 조회. 삭제/미선택이면 아무것도 그리지 않는다.
        if let theme = manager.customThemes.first(where: { $0.id == themeID }) {
            editorSections(for: theme)
        }
    }

    @ViewBuilder
    private func editorSections(for theme: CustomTheme) -> some View {
        Section {
            TextField("테마 이름", text: nameBinding)
                .textFieldStyle(.roundedBorder)
            Toggle("어두운 테마", isOn: isDarkBinding)
        } header: {
            Text("편집 중: \(theme.name)")
        } footer: {
            Text("색을 바꾸면 앱 전체에 즉시 반영됩니다. 각 색 오른쪽 ↺로 베이스 프리셋(\(theme.basePalette.displayName)) 값으로 되돌립니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            LazyVGrid(columns: slotColumns, alignment: .leading, spacing: 8) {
                ForEach(ThemeColorSlot.allCases) { slot in
                    slotCell(slot, theme: theme)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("색 슬롯")
        }
    }

    private func slotCell(_ slot: ThemeColorSlot, theme: CustomTheme) -> some View {
        HStack(spacing: 6) {
            ColorPicker(selection: colorBinding(slot), supportsOpacity: false) {
                Text(slot.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            Button {
                resetSlot(slot)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("\(slot.displayName)을(를) 베이스 프리셋 값으로 되돌립니다")
            // 이미 프리셋 기본값과 같으면 리셋할 게 없으므로 비활성.
            .disabled(isSlotAtBase(slot, theme: theme))
        }
    }

    // MARK: - 바인딩 (setter는 항상 매니저에서 최신 값을 재조회 — 스테일 스냅샷 방지)

    private func current() -> CustomTheme? {
        manager.customThemes.first(where: { $0.id == themeID })
    }

    private func colorBinding(_ slot: ThemeColorSlot) -> Binding<Color> {
        Binding(
            get: {
                guard let t = current() else { return .gray }
                return ColorHex.color(t[slot]) ?? t.basePalette[keyPath: slot.paletteKeyPath]
            },
            set: { newColor in
                guard var t = current() else { return }
                t[slot] = ColorHex.hex(newColor)
                manager.updateCustomTheme(t)
            }
        )
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { current()?.name ?? "" },
            set: { newName in
                guard var t = current() else { return }
                t.name = newName
                manager.updateCustomTheme(t)
            }
        )
    }

    private var isDarkBinding: Binding<Bool> {
        Binding(
            get: { current()?.isDark ?? false },
            set: { newValue in
                guard var t = current() else { return }
                t.isDark = newValue
                manager.updateCustomTheme(t)
            }
        )
    }

    private func resetSlot(_ slot: ThemeColorSlot) {
        guard var t = current() else { return }
        t.resetSlot(slot)
        manager.updateCustomTheme(t)
    }

    /// 현재 슬롯 hex가 베이스 프리셋 슬롯 값과 동일한지(리셋 버튼 활성/비활성 판단).
    private func isSlotAtBase(_ slot: ThemeColorSlot, theme: CustomTheme) -> Bool {
        theme[slot].uppercased() == ColorHex.hex(theme.basePalette[keyPath: slot.paletteKeyPath]).uppercased()
    }
}
