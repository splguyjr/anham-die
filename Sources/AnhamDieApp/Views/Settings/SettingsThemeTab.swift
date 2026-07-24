import SwiftUI

/// 설정 '테마' 탭 (PLAN §13.2) — 프리셋 팔레트 갤러리 + 강조색 ColorPicker.
///
/// 변경은 `settings.selectedThemeID`(갤러리)·`settings.accentColorHex`(피커) 두 값만 건드리고
/// (= ThemeManager가 노출하는 것과 동일 저장소), AppTheme.* 색이 이 두 값을 경유하므로 앱 전역이
/// 즉시 재평가된다. 팔레트 프리뷰/선택 인디케이터도 팔레트 자체 색(background/surface/textPrimary/
/// accent)만 그린다 — 하드코딩 색 없음(§13.2 규칙).
struct SettingsThemeTab: View {
    @Bindable private var settings = AppContext.shared.settings
    private var theme: ThemeManager { AppContext.shared.theme }

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 12)]

    var body: some View {
        Form {
            // 프리셋 팔레트 갤러리
            Section {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ThemePalette.all) { palette in
                        Button {
                            settings.selectedThemeID = palette.id
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

            // 강조색 오버라이드
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
                Text("강조색은 선택 표시·인디케이터·버튼 등에 쓰입니다. 비워 두면 팔레트의 기본 강조색을 사용합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 강조색 바인딩

    /// 현재 유효 강조색(오버라이드 또는 팔레트 기본)을 보여주고, 고르면 hex로 영속한다.
    /// nil 상태에서 팔레트를 바꾸면 get이 새 팔레트 기본색을 반환하므로 피커도 따라 갱신된다.
    private var accentBinding: Binding<Color> {
        Binding(
            get: { theme.accent },
            set: { settings.accentColorHex = ColorHex.hex($0) }
        )
    }

    private var accentStateLabel: String {
        settings.accentColorHex == nil ? "팔레트 기본 강조색 사용 중" : "사용자 지정 강조색 사용 중"
    }
}

/// 팔레트 미리보기 썸네일 — 팔레트의 배경/표면/텍스트/강조색만으로 축소 카드 UI를 그린다.
private struct ThemePaletteThumbnail: View {
    let palette: ThemePalette
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            preview
                .frame(height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? AppTheme.accent : AppTheme.divider,
                            lineWidth: isSelected ? 2.5 : 1
                        )
                )

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
