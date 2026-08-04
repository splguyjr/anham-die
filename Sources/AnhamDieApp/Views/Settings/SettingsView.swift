import AppKit
import SwiftUI
import KeyboardShortcuts

/// 설정 창 (PLAN §3.4, §13.2): 일반 / 단축키 / 오버레이 / 테마 / 태그 관리 탭.
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
            SettingsThemeTab()
                .tabItem { Label("테마", systemImage: "paintpalette") }
            SettingsTagsTab()
                .tabItem { Label("태그", systemImage: "tag") }
        }
        // v7: 테마 탭(프리셋 9종 갤러리+내 테마+12슬롯 편집기) 세로 분량 대응 — 전 탭 공용 프레임 상향.
        .frame(width: 480, height: 520)
        // 선택 팔레트의 명암을 설정 창 전체에 반영 — 다크 팔레트에서 Form이 라이트로 남지 않도록(§13.2).
        .preferredColorScheme(AppContext.shared.theme.palette.isDark ? .dark : .light)
    }
}

// MARK: - 일반

private struct SettingsGeneralTab: View {
    @Bindable private var settings = AppContext.shared.settings
    @State private var showInstallRequiredAlert = false

    // 인덱스+1 = Calendar.weekday 값(1=일 … 7=토, settings.weekStartDay와 동일 규약).
    private static let weekdayNames = ["일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]

    var body: some View {
        Form {
            Section {
                Toggle("로그인 시 자동 실행", isOn: launchAtLoginBinding)
                Toggle("Dock 아이콘 표시", isOn: dockIconBinding)
            }
            Section {
                Toggle("메모 미리보기 표시", isOn: $settings.showNotePreview)
            } footer: {
                Text("메모가 있는 할 일은 목록·브리핑에서 제목 아래에 메모 첫 줄을 함께 보여줍니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Section {
                Picker("주 시작 요일", selection: $settings.weekStartDay) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Self.weekdayNames[day - 1]).tag(day)
                    }
                }
            } footer: {
                Text("주간 목표와 주간 리뷰가 이 요일을 한 주의 시작으로 계산합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("설치된 앱에서만 켤 수 있습니다", isPresented: $showInstallRequiredAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("로그인 시 자동 실행은 Applications 폴더에 설치된 AnhamDie에서만 켤 수 있습니다. Scripts/build-app.sh --install로 ~/Applications에 설치한 뒤 다시 시도하세요.")
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { newValue in
                // 임시 경로(dist/·swift run)에서 등록하면 다음 빌드에서 깨진 로그인 항목이 남으므로
                // 설치본이 아니면 등록하지 않고 토글을 되돌린다.
                if newValue && !LaunchAtLoginService.isRunningFromApplications {
                    settings.launchAtLogin = false
                    showInstallRequiredAlert = true
                    return
                }
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
                try LaunchAtLoginService.register()
            } else {
                try LaunchAtLoginService.unregister()
            }
        } catch {
            NSLog("AnhamDie: 로그인 항목 설정 실패 — \(error)")
        }
    }
}

// MARK: - 단축키 (PLAN §11.4 — 마스터 → 개별(토글+Recorder) → 예외 앱)

private struct SettingsShortcutsTab: View {
    @Bindable private var settings = AppContext.shared.settings
    /// 예외 앱 직접 입력용 번들 ID
    @State private var newBundleID = ""

    /// 접두사 → 친숙한 표시명 (기본값 등 잘 알려진 항목)
    private static let knownPrefixLabels: [String: String] = [
        "com.jetbrains.": "JetBrains 계열 (IntelliJ, PyCharm 등)"
    ]

    var body: some View {
        Form {
            // 마스터 토글
            Section {
                Toggle("전역 단축키 사용", isOn: $settings.hotkeysMasterEnabled)
            } footer: {
                Text("끄면 아래 모든 단축키가 즉시 비활성화됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 개별 토글 + Recorder
            Section {
                ForEach(HotkeyService.allNames, id: \.rawValue) { name in
                    HStack(spacing: 12) {
                        Toggle(HotkeyService.displayName(for: name), isOn: hotkeyEnabledBinding(name))
                        Spacer(minLength: 12)
                        KeyboardShortcuts.Recorder(for: name)
                    }
                }
            } header: {
                Text("단축키")
            } footer: {
                Text("전역 단축키입니다. 다른 앱을 쓰는 중에도 동작합니다. 개별 스위치로 끄거나 우측에서 직접 지정하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.hotkeysMasterEnabled)

            // 예외 앱
            Section {
                if settings.hotkeyExceptionAppPrefixes.isEmpty {
                    Text("예외 앱이 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.hotkeyExceptionAppPrefixes, id: \.self) { prefix in
                        exceptionRow(prefix)
                    }
                }

                HStack(spacing: 8) {
                    TextField("번들 ID 또는 접두사 (예: com.jetbrains.)", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addTypedPrefix() }
                    Button("추가") { addTypedPrefix() }
                        .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Menu("실행 중 앱에서 추가") {
                    let apps = runningApps
                    if apps.isEmpty {
                        Text("실행 중인 앱이 없습니다")
                    } else {
                        ForEach(apps, id: \.bundleID) { app in
                            Button(app.name) { addPrefix(app.bundleID) }
                        }
                    }
                }
            } header: {
                Text("예외 앱")
            } footer: {
                Text("이 목록의 앱이 활성화되어 있는 동안 전역 단축키를 잠시 양보합니다(예: IntelliJ 단축키 충돌 방지). 번들 ID 접두사로 일치하므로 \"com.jetbrains.\"는 JetBrains 계열 전체에 적용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: 행

    @ViewBuilder
    private func exceptionRow(_ prefix: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                // 설정 창은 색상 스킴을 강제하지 않으므로 다크 모드 대비 위해 적응형 색을 쓴다(부제 .secondary와 일관).
                Text(displayLabel(for: prefix))
                    .foregroundStyle(.primary)
                if displayLabel(for: prefix) != prefix {
                    Text(prefix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                removePrefix(prefix)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("제거")
        }
        .padding(.vertical, 1)
    }

    // MARK: 바인딩·동작

    private func hotkeyEnabledBinding(_ name: KeyboardShortcuts.Name) -> Binding<Bool> {
        Binding(
            get: { !settings.disabledHotkeyIDs.contains(name.rawValue) },
            set: { enabled in
                var ids = settings.disabledHotkeyIDs
                if enabled { ids.remove(name.rawValue) } else { ids.insert(name.rawValue) }
                settings.disabledHotkeyIDs = ids
            }
        )
    }

    private func addTypedPrefix() {
        let trimmed = newBundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        addPrefix(trimmed)
        newBundleID = ""
    }

    private func addPrefix(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var list = settings.hotkeyExceptionAppPrefixes
        guard !list.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        list.append(trimmed)
        settings.hotkeyExceptionAppPrefixes = list
    }

    private func removePrefix(_ prefix: String) {
        settings.hotkeyExceptionAppPrefixes = settings.hotkeyExceptionAppPrefixes.filter { $0 != prefix }
    }

    // MARK: 표시 헬퍼

    /// 접두사의 사람이 읽기 좋은 이름: 알려진 라벨 → 현재 실행 중 일치 앱 이름 → 원본 문자열
    private func displayLabel(for prefix: String) -> String {
        if let known = Self.knownPrefixLabels[prefix.lowercased()] { return known }
        if let match = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier?.caseInsensitiveCompare(prefix) == .orderedSame
        }), let name = match.localizedName {
            return name
        }
        return prefix
    }

    /// frontmost로 뜰 수 있는(일반) 실행 중 앱 목록 — 번들 ID 기준 중복 제거·이름순
    private var runningApps: [(name: String, bundleID: String)] {
        var seen = Set<String>()
        var result: [(name: String, bundleID: String)] = []
        for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            result.append((name: app.localizedName ?? bundleID, bundleID: bundleID))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    // hex 왕복은 ColorHex 단일 경로(§15.1) — 파싱 실패 시 기본 태그 회색 폴백.
    private var colorBinding: Binding<Color> {
        Binding(
            get: { ColorHex.color(tag.colorHex) ?? Color(.sRGB, red: 0.56, green: 0.56, blue: 0.58, opacity: 1) },
            set: { tag.colorHex = ColorHex.hex($0); store.notifyChanged() }
        )
    }
}
