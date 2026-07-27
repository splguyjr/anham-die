import SwiftUI

/// 설정 '테마' 탭 (PLAN §13.2 · v7 §15.1) — 프리셋 갤러리 + 강조색 피커 + 내 테마(커스텀) + 편집기.
///
/// 구성(§15.1): ① 프리셋 갤러리(9종, 썸네일이 배경/표면/강조/텍스트 동시 노출) → ② 강조색 간이 피커
/// (프리셋 선택 시 유지, 커스텀 선택 중엔 비활성) → ③ 내 테마 섹션(커스텀 나열·+ 새 테마=선택 테마 복제·
/// 복제·삭제) → ④ 편집기(선택된 커스텀일 때 12슬롯 ColorPicker + isDark). 변경은 ThemeManager 경유로
/// 전역 실시간 반영된다. 미리보기·썸네일은 resolvedPalette(for:)만 쓰고 하드코딩 색은 없다.
struct SettingsThemeTab: View {
    @Bindable private var settings = AppContext.shared.settings
    private var theme: ThemeManager { AppContext.shared.theme }

    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 200), spacing: 12)]

    var body: some View {
        Form {
            presetSection
            accentSection
            customSection
            if let custom = theme.selectedCustomTheme {
                ThemeEditorView(themeID: custom.id)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - ① 프리셋 갤러리

    private var presetSection: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(ThemePalette.all) { palette in
                    Button {
                        theme.selectedThemeID = palette.id
                    } label: {
                        ThemePaletteThumbnail(
                            palette: palette,
                            isSelected: settings.selectedThemeID == palette.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("팔레트")
        } footer: {
            Text("앱 전체의 배경·표면·텍스트·기본 강조색을 정의합니다. 선택 즉시 모든 창에 반영됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - ② 강조색 오버라이드 (프리셋 선택 시 유지 — 커스텀 선택 중엔 편집기 '강조' 슬롯 사용)

    private var accentSection: some View {
        Section {
            ColorPicker("강조색", selection: accentBinding, supportsOpacity: false)
            HStack {
                Text(accentStateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("팔레트 기본값으로") {
                    settings.accentColorHex = nil
                }
                .disabled(settings.accentColorHex == nil)
            }
        } header: {
            Text("강조색")
        } footer: {
            Text(accentFooterText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // 커스텀 테마는 accent 슬롯이 곧 강조색이라, 모노는 §15.2 무채 규칙으로 오버라이드가
        // 무시되므로 각각 비활성화한다 — 무시될 값을 새로 설정할 수 없어야 한다.
        .disabled(theme.isCustomThemeSelected || theme.palette.monochrome)
    }

    // MARK: - ③ 내 테마 (커스텀 목록 + 새 테마)

    private var customSection: some View {
        Section {
            if theme.customThemes.isEmpty {
                Text("저장된 커스텀 테마가 없습니다. 아래에서 현재 선택한 테마를 복제해 새로 만드세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(theme.customThemes) { custom in
                    CustomThemeRow(
                        custom: custom,
                        isSelected: settings.selectedThemeID == custom.id.uuidString
                    )
                }
            }

            Button {
                let created = theme.createCustomTheme(basedOn: settings.selectedThemeID)
                theme.selectedThemeID = created.id.uuidString
            } label: {
                Label("새 테마 (선택한 테마 복제)", systemImage: "plus")
            }
        } header: {
            Text("내 테마")
        } footer: {
            Text("커스텀 테마는 12색 슬롯을 직접 편집할 수 있습니다. 선택하면 아래에 편집기가 열립니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 강조색 바인딩

    /// 현재 유효 강조색(오버라이드 또는 팔레트 기본)을 보여주고, 고르면 hex로 영속한다.
    private var accentBinding: Binding<Color> {
        Binding(
            get: { theme.accent },
            set: { settings.accentColorHex = ColorHex.hex($0) }
        )
    }

    private var accentStateLabel: String {
        if theme.palette.monochrome {
            return "모노 테마 — 무채 강조색 사용 중"
        }
        return settings.accentColorHex == nil ? "팔레트 기본 강조색 사용 중" : "사용자 지정 강조색 사용 중"
    }

    private var accentFooterText: String {
        if theme.palette.monochrome {
            return "모노 테마는 지난 일정의 빨강만 남기고 전체가 회색조로 표시되어 강조색을 쓰지 않습니다. 저장된 강조색은 다른 팔레트를 선택하면 다시 적용됩니다."
        }
        if theme.isCustomThemeSelected {
            return "커스텀 테마를 쓰는 중입니다. 강조색은 아래 편집기의 '강조' 슬롯에서 바꿉니다."
        }
        return "강조색은 선택 표시·인디케이터·버튼 등에 쓰입니다. 비워 두면 팔레트의 기본 강조색을 사용합니다."
    }
}

// MARK: - 커스텀 테마 행 (선택 · 복제 · 삭제)

/// 내 테마 목록의 한 행 — 스와치 스트립 + 이름 + 선택 표시 + (⋯ 복제·삭제) 메뉴.
/// 스와치/색은 resolvedPalette(for:) 경유라 편집이 이 행에도 실시간 반영된다.
private struct CustomThemeRow: View {
    let custom: CustomTheme
    let isSelected: Bool

    private var theme: ThemeManager { AppContext.shared.theme }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                theme.selectedThemeID = custom.id.uuidString
            } label: {
                HStack(spacing: 10) {
                    ThemeSwatchStrip(palette: theme.resolvedPalette(for: custom.id.uuidString))
                        .frame(width: 60, height: 20)
                    Text(custom.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    if let copy = theme.duplicateCustomTheme(id: custom.id) {
                        theme.selectedThemeID = copy.id.uuidString
                    }
                } label: {
                    Label("복제", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) {
                    theme.deleteCustomTheme(id: custom.id)
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("이 테마 복제·삭제")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(custom.name) 커스텀 테마")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// 4색 스와치 스트립(배경·표면·강조·텍스트) — 인접한 유사색도 위치·테두리로 구분되게 그린다.
private struct ThemeSwatchStrip: View {
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 0) {
            swatch(palette.background)
            swatch(palette.surface)
            swatch(palette.accent)
            swatch(palette.textPrimary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(AppTheme.divider, lineWidth: 1)
        )
    }

    private func swatch(_ color: Color) -> some View {
        Rectangle().fill(color)
    }
}

/// 팔레트 미리보기 썸네일 — 배경/표면/강조/텍스트를 축소 리스트 카드 + 하단 4색 스트립으로 동시에 보여준다(§15.1·§15.3).
private struct ThemePaletteThumbnail: View {
    let palette: ThemePalette
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            preview
                .frame(height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? AppTheme.accent : AppTheme.divider,
                            lineWidth: isSelected ? 2.5 : 1
                        )
                )

            // 배경/표면/강조/텍스트 4색 스와치 스트립 — 기본 vs 모노처럼 인접 유사색도 육안 구분되게(§15.3).
            ThemeSwatchStrip(palette: palette)
                .frame(height: 12)

            Text(palette.displayName)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(palette.displayName) 테마")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var preview: some View {
        ZStack(alignment: .topTrailing) {
            palette.background

            // 표면 카드 위에 텍스트 두 줄 + 강조 점을 얹어 실제 리스트 행 느낌을 축약.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.surface)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        bar(palette.textPrimary, width: 46, height: 6)
                        bar(palette.textSecondary, width: 34, height: 5)
                        Spacer(minLength: 0)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(palette.accent)
                                .frame(width: 11, height: 11)
                            bar(palette.divider, width: 26, height: 5)
                        }
                    }
                    .padding(9)
                }
                .padding(8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(palette.surface, palette.accent)
                    .padding(5)
            }
        }
    }

    private func bar(_ color: Color, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
    }
}
