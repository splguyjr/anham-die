import SwiftUI
import ServiceManagement
import KeyboardShortcuts

/// 설정 창 (PLAN §3.4): 일반 / 단축키 / 오버레이 / 태그 관리 탭.
/// 모든 값은 AppSettings·TaskStore에 연동되고 변경 즉시 반영된다.
struct SettingsView: View {
    var body: some View {
        TabView {
            SettingsGeneralTab()
                .tabItem { Label("일반", systemImage: "gearshape") }
            SettingsShortcutsTab()
                .tabItem { Label("단축키", systemImage: "keyboard") }
            SettingsOverlayTab()
                .tabItem { Label("오버레이", systemImage: "rectangle.on.rectangle") }
            SettingsTagsTab()
                .tabItem { Label("태그", systemImage: "tag") }
        }
        .frame(width: 460, height: 380)
    }
}

// MARK: - 일반

private struct SettingsGeneralTab: View {
    @Bindable private var settings = AppContext.shared.settings

    var body: some View {
        Form {
            Section {
                Toggle("로그인 시 자동 실행", isOn: launchAtLoginBinding)
                Toggle("Dock 아이콘 표시", isOn: dockIconBinding)
            }
            Section {
                DatePicker(
                    "하루 기준 시각",
                    selection: dayBoundaryBinding,
                    displayedComponents: .hourAndMinute
                )
            } footer: {
                Text("이 시각을 넘겨야 새로운 하루로 넘어갑니다. 이후 첫 활성화 때 어제 미완료 목록을 확인합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { newValue in
                settings.launchAtLogin = newValue
                applyLaunchAtLogin(newValue)
            }
        )
    }

    private var dockIconBinding: Binding<Bool> {
        Binding(
            get: { settings.showDockIcon },
            set: { newValue in
                settings.showDockIcon = newValue
                NSApp.setActivationPolicy(newValue ? .regular : .accessory)
            }
        )
    }

    private var dayBoundaryBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = settings.dayBoundaryHour
                comps.minute = settings.dayBoundaryMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.dayBoundaryHour = comps.hour ?? 9
                settings.dayBoundaryMinute = comps.minute ?? 0
            }
        )
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("AnhamDie: 로그인 항목 설정 실패 — \(error)")
        }
    }
}

// MARK: - 단축키

private struct SettingsShortcutsTab: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("브리핑 토글", name: .toggleBriefing)
                KeyboardShortcuts.Recorder("오버레이 토글", name: .toggleOverlay)
                KeyboardShortcuts.Recorder("빠른 추가", name: .quickAdd)
            } footer: {
                Text("전역 단축키입니다. 다른 앱을 쓰는 중에도 동작합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 오버레이

private struct SettingsOverlayTab: View {
    @Bindable private var settings = AppContext.shared.settings

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("배경 불투명도")
                        Spacer()
                        Text("\(Int((settings.overlayOpacity * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.overlayOpacity, in: 0.3...1.0)
                }
            }
            Section {
                Stepper(
                    "최대 표시 개수: \(settings.overlayMaxCount)개",
                    value: $settings.overlayMaxCount,
                    in: 1...20
                )
            } footer: {
                Text("오버레이에는 오늘 할 일 중 이 개수까지만 표시하고, 초과분은 \"+N개\"로 묶어 보여줍니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 태그 관리

private struct SettingsTagsTab: View {
    // TaskStore(@Observable)의 tags 배열을 body에서 읽어 관찰을 성립시킨다.
    private var store: TaskStore { AppContext.shared.store }

    var body: some View {
        let tags = store.tags
        return VStack(spacing: 0) {
            if tags.isEmpty {
                Spacer()
                Text("태그가 없습니다. 아래에서 추가하세요.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(tags) { tag in
                        SettingsTagRow(tag: tag)
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Spacer()
                Button {
                    store.addTag(Tag(name: "새 태그", colorHex: "#8E8E93"))
                } label: {
                    Label("태그 추가", systemImage: "plus")
                }
            }
            .padding(12)
        }
    }
}

private struct SettingsTagRow: View {
    let tag: Tag
    private var store: TaskStore { AppContext.shared.store }

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
            TextField("태그 이름", text: nameBinding)
                .textFieldStyle(.roundedBorder)
            Button(role: .destructive) {
                store.removeTag(tag)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { tag.name },
            set: { tag.name = $0; store.notifyChanged() }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(anhamHex: tag.colorHex) },
            set: { tag.colorHex = anhamHexString(from: $0); store.notifyChanged() }
        )
    }
}

// MARK: - 색상 <-> 헥스 변환 (파일 내부 전용)

fileprivate extension Color {
    init(anhamHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
        } else {
            r = 0.56; g = 0.56; b = 0.58
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

fileprivate func anhamHexString(from color: Color) -> String {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.gray
    let r = Int((ns.redComponent * 255).rounded())
    let g = Int((ns.greenComponent * 255).rounded())
    let b = Int((ns.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", r, g, b)
}
