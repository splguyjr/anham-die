# TO-DO 앱 기획서 (가칭: anham-die)

> macOS 네이티브 투두 앱. Scribble 앱의 미니멀한 감성을 기반으로,
> **데스크톱 위젯 모드**와 **화면 맨 앞 플로팅 오버레이 모드**를 지원하고,
> 알림 대신 **트리거 기반 브리핑 + Jira식 이월**로 하루를 관리한다.

작성일: 2026-07-22 · 상태: 기획 확정, 구현 전

---

## 1. 확정된 요구사항 요약

| 항목 | 결정 |
|---|---|
| 플랫폼 / 타깃 | macOS 15+ 전용, 로컬 전용(동기화 없음) |
| 기술 스택 | Swift + SwiftUI + SwiftData (+ 일부 AppKit) |
| UI 스타일 | Scribble 앱 스타일 미니멀 리스트 (인라인 Add task, 체크박스, 색상 점 마커) |
| 앱 형태 | 메뉴바 상주가 기본, 설정에서 Dock 아이콘 표시 토글 |
| 표시 모드 | ① 메인 창 ② 데스크톱 위젯(인터랙티브 체크) ③ 컴팩트 플로팅 오버레이 |
| Due 관리 | 날짜 기반 D-day/색상 표시. 푸시 알림 없음 |
| 브리핑 | 로그인·앱 시작 / 글로벌 단축키 / 매일 특정 시각 — 세 트리거로 "지금 해야 할 목록" 패널 표시 |
| 이월 | 확인 후 이월. 하루 기준 시각(기본 오전 9시) 이후 첫 활성화 때 어제 미완료 목록을 보여주고 선택 |
| 부가 기능 | 우선순위, 태그/라벨, 완료 히스토리, 서브태스크/메모 |
| 자동 실행 | 로그인 시 자동 실행 (설정에서 on/off) |

---

## 2. 핵심 컨셉: "논리적 하루"와 브리핑

이 앱의 하루는 자정이 아니라 **기준 시각(기본 오전 9시, 설정 가능)**에 시작한다.
새벽 2시에 작업 중이라면 아직 "어제"다.

### 2.1 브리핑 트리거

다음 이벤트가 발생하면 브리핑 노출 여부를 판단한다:

1. **앱 시작 / 로그인 자동 실행 시**
2. **잠자기 해제(노트북 덮었다 열기)** — `NSWorkspace.didWakeNotification`으로 감지 가능.
   → 사용자가 궁금해했던 부분: **가능하다.** 슬립 해제도 "첫 실행"처럼 취급할 수 있다.
3. **매일 기준 시각 도달** (앱이 이미 켜져 있을 때 타이머로)
4. **글로벌 단축키** (기본값 미정, 예: ⌥⌘T) — 이건 판단 없이 **항상** 즉시 표시/숨김

### 2.2 브리핑 노출 판단 로직

```
트리거 발생(시작/웨이크/시각 도달) 시:
  today = 기준시각(9시) 기준의 논리적 오늘 날짜
  if lastBriefingDate < today:
      브리핑 패널 표시
      lastBriefingDate = today
```

- 하루에 한 번만 자동으로 뜨고, 그 이후엔 단축키/메뉴바로만 호출.
- 단축키 호출 시에는 lastBriefingDate와 무관하게 항상 표시.

### 2.3 브리핑 패널 내용

- **오늘 할 일 목록** (오늘로 예정된 것 + due가 오늘인 것)
- **어제(이전 논리적 하루) 미완료 작업 N개** → 항목별 또는 일괄로 선택:
  - **오늘로 가져오기** → `scheduledDate = 오늘`, `rolloverCount += 1` (↺2 처럼 배지 표시)
  - **보류(Backlog)** → 날짜 없는 백로그로 이동
  - **버리기** → 삭제(또는 취소 처리로 히스토리에 남김)
- due 초과(overdue) 항목은 빨간색으로 강조

---

## 3. 화면 구성

### 3.1 메인 창 — Scribble 스타일

첨부 스크린샷 기준으로 재현:

- 상단: 앱 로고(색 점) + 타이틀, 우측 `…` 메뉴
- 최상단 행이 곧 입력창: 체크박스 + "Add task" 플레이스홀더, 엔터로 추가
- 리스트 행: 체크박스 · 제목 · 우선순위/태그 색 점 · D-day 배지 · 이월 배지(↺n)
- 행 클릭(또는 펼침)으로 상세: 메모, 서브태스크 체크리스트, due 날짜, 태그, 우선순위
- 뷰 전환: **오늘 / 예정(due 있는 것) / 백로그 / 완료(히스토리)**
- 완료 히스토리: 날짜별 그룹으로 완료 기록 조회
- Due 색상 규칙: 지남=빨강, 오늘=주황, 임박(≤3일)=노랑, 여유=회색 D-day

### 3.2 컴팩트 플로팅 오버레이

```
┌──────────────────┐
│ 🔴 오늘 할 일  3/7 │
├──────────────────┤
│ ☐ 결제 워크플로우 🔴 │
│ ☐ Docker 실습      │
│ ☑ 도시락 통 알아보기 │
│ ↺ 이월됨 2개        │
└──────────────────┘
```

- 오늘 할 일만 담은 작은 카드, **모든 Spaces·전체화면 앱 위에도 표시**
- 항상 위(floating level), 드래그로 이동, 위치 기억
- 반투명도 조절(설정), 체크박스 클릭으로 바로 완료 처리
- 헤더에 진행률(3/7), 단축키/메뉴바로 표시·숨김 토글
- 브리핑 패널은 이 오버레이의 "이월 제안 섹션이 붙은 확장 형태"로 구현하면 재사용 가능

### 3.3 데스크톱 위젯 (WidgetKit)

- **오늘 할 일 + 바로 체크**: 위젯에서 체크박스 클릭 시 앱 안 열고 완료 처리 (인터랙티브 위젯, AppIntents)
- 크기: small(개수+최상위 2개) / medium(4~5개) / large(8~10개)
- 남은 개수·진행률 헤더, overdue는 빨간 표시
- 데이터는 App Group 컨테이너로 앱과 공유, 변경 시 `WidgetCenter.shared.reloadAllTimelines()`

### 3.4 메뉴바 & 설정

- 메뉴바 아이콘: 클릭 시 팝오버(오늘 목록 요약 + 브리핑 열기 + 오버레이 토글 + 메인 창 열기)
- 설정 화면:
  - 로그인 시 자동 실행 on/off
  - Dock 아이콘 표시 on/off
  - 하루 기준 시각 (기본 09:00)
  - 글로벌 단축키 지정 (브리핑 토글 / 오버레이 토글 / 빠른 추가)
  - 오버레이 투명도·클릭 동작
  - 태그 관리 (이름·색상)

---

## 4. 데이터 모델 (SwiftData 초안)

```swift
@Model class TodoTask {
    var id: UUID
    var title: String
    var note: String              // 메모
    var createdAt: Date
    var scheduledDate: Date?      // 어느 "논리적 하루"에 속하는지. nil = 백로그
    var dueDate: Date?            // 목표 마감일 (D-day 계산용)
    var completedAt: Date?        // nil = 미완료. 값 있으면 완료 히스토리에 포함
    var priority: Priority        // high / normal / low
    var rolloverCount: Int        // 이월 횟수 (↺n 배지)
    var sortOrder: Int
    var tags: [Tag]               // 다대다
    var subtasks: [Subtask]       // 일대다, cascade delete
}

@Model class Subtask {
    var title: String
    var isDone: Bool
    var sortOrder: Int
}

@Model class Tag {
    var name: String
    var colorHex: String          // 리스트에서 색 점으로 표시
}
```

- 완료 = 삭제가 아니라 `completedAt` 기록 → 완료 히스토리가 공짜로 생김
- "오늘 할 일" 쿼리: `scheduledDate == 논리적오늘 || (dueDate == 오늘 && 미완료)`
- 저장소는 App Group 컨테이너에 두어 위젯과 공유:
  `ModelConfiguration(groupContainer: .identifier("group.<번들ID>"))`

---

## 5. 기술 설계 포인트

### 5.1 프로젝트 구조 (Xcode 타깃)

```
AnhamDie/
├─ App/                  # 메인 앱 타깃 (SwiftUI)
│  ├─ Views/             # 메인 창, 오버레이, 브리핑, 설정, 메뉴바 팝오버
│  ├─ Models/            # SwiftData 모델 (위젯과 공유 → 별도 그룹/패키지로)
│  ├─ Services/          # DayBoundaryService, RolloverService, TriggerService
│  └─ AppKit/            # FloatingPanel(NSPanel) 래퍼
├─ Widget/               # 위젯 익스텐션 타깃 (WidgetKit + AppIntents)
└─ Shared/               # 모델·쿼리·App Group 상수 (양쪽 타깃 멤버십)
```

### 5.2 모드별 핵심 API

| 기능 | 구현 방법 |
|---|---|
| 플로팅 오버레이 | `NSPanel`(nonactivatingPanel) + `NSHostingView`. `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `isMovableByWindowBackground = true`. SwiftUI만의 `.windowLevel(.floating)`(macOS 15)도 있지만 전체화면 위 표시·비활성화 클릭엔 NSPanel이 확실 |
| 위젯 바로 체크 | `AppIntent`(ToggleTaskIntent) + `Button(intent:)` in widget view |
| 로그인 자동 실행 | `SMAppService.mainApp.register()` / `.unregister()` (macOS 13+) |
| Dock 표시 토글 | `NSApp.setActivationPolicy(.regular / .accessory)` |
| 메뉴바 상주 | SwiftUI `MenuBarExtra` |
| 웨이크 감지 | `NSWorkspace.shared.notificationCenter` → `didWakeNotification` |
| 기준 시각 도달 | 앱 상주 중 `Timer`(다음 9시까지) + 웨이크 시 재계산 |
| 글로벌 단축키 | [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 패키지 (사용자 지정 UI까지 제공) — 유일한 외부 의존성 |

### 5.3 주의할 점

- **App Group / 위젯은 코드 서명 필요** → 개인 팀(무료 Apple ID)으로 로컬 빌드 가능. 배포 계획 생기면 유료 개발자 계정 필요
- 위젯 타임라인은 시스템이 갱신 주기를 제한하므로, 앱에서 데이터 변경 시마다 명시적으로 reload 호출
- 논리적 하루 계산은 한 곳(`DayBoundaryService`)에 몰아넣기 — 메인/오버레이/위젯/이월이 전부 같은 정의를 써야 함
- 오버레이가 포커스를 뺏으면 짜증나므로 nonactivating panel로 클릭해도 현재 앱 포커스 유지

---

## 6. 구현 순서 (마일스톤)

| 단계 | 내용 | 결과물 |
|---|---|---|
| **M1** | 프로젝트 셋업 + SwiftData 모델 + 메인 창 (Scribble 스타일 리스트, 추가/체크/삭제, due·D-day 표시) | 기본 투두 앱으로 쓸 수 있음 |
| **M2** | 메뉴바 상주 + Dock 토글 + 로그인 자동 실행 + 설정 창 | 상주 앱 골격 완성 |
| **M3** | 논리적 하루 + 브리핑 패널 + 이월 플로우 (시작/웨이크/시각 트리거) | 핵심 차별 기능 |
| **M4** | 컴팩트 플로팅 오버레이 + 글로벌 단축키 | 화면 맨 앞 모드 |
| **M5** | 위젯 (인터랙티브 체크, 3가지 크기) | 위젯 모드 |
| **M6** | 폴리시: 태그 관리·필터, 우선순위 정렬, 서브태스크 UI, 완료 히스토리 뷰, 애니메이션 | 완성도 |

각 단계가 독립적으로 동작하는 상태로 끝나므로 중간에 멈춰도 쓸 수 있는 앱이 남는다.

---

## 7. 확정 사항 (2026-07-22 최종)

- [x] 앱 이름 **AnhamDie** / 번들 ID `com.splguyjr.anhamdie`
- [x] 글로벌 단축키 기본값: 브리핑 ⌥⌘T · 오버레이 ⌥⌘O · 빠른 추가 ⌥⌘N (설정에서 변경 가능)
- [x] 이월 "버리기" = 완전 삭제가 아니라 **'취소됨' 상태로 히스토리 보관** (복구 가능)
- [x] 완료 항목: 리스트 **하단 취소선 표시 → 다음 논리적 하루에 숨김** (히스토리에서 조회)
- [x] 오버레이 최대 표시 개수 기본 7개 (설정 조절), 초과분은 "+N개" 표시
- [x] 빠른 추가 기능 **포함** (어디서든 ⌥⌘N → Spotlight식 입력창, Enter로 오늘에 추가, Esc 닫기)

## 8. 빌드 전략 (환경 제약 반영)

이 Mac에는 Xcode가 없고 Command Line Tools만 있다 (Xcode는 App Store에서 설치 진행 중).

- **1차 (오늘 밤, SPM만으로)**: SPM 실행파일 타깃으로 메인 앱 전체 빌드.
  `Scripts/build-app.sh`가 release 빌드 → .app 번들 조립(Info.plist `LSUIElement=true`,
  `CFBundleIdentifier=com.splguyjr.anhamdie`, min macOS 15) → ad-hoc 서명 → `~/Applications` 설치.
  위젯 제외 전 기능 동작. 데이터는 우선 `~/Library/Application Support/AnhamDie/`.
- **2차 (Xcode 준비 후)**: `project.yml`(XcodeGen)로 앱+위젯 익스텐션 프로젝트 생성 →
  `Scripts/build-with-xcode.sh`로 빌드. App Group 컨테이너로 저장소 이전(마이그레이션 포함).
  위젯 서명에는 Xcode에 Apple ID 로그인(무료 개인 팀)이 필요.
- 저장소는 `TaskStore` 프로토콜 뒤로 추상화 — CLT 툴체인에서 SwiftData 매크로가 문제되면
  Codable JSON 스토어로 교체 가능하게. Swift tools 6.0 + 언어 모드 v5(엄격 동시성 완화). UI는 한국어.

---

## 9. 구현 현황 (2026-07-23 새벽, 최종 취합 게이트 기준)

### 완료

- **M1–M4, M6 전부**: 메인 창(오늘/예정/백로그/완료 4뷰, 인라인 추가, 상세 편집,
  D-day 색상, 이월 배지) · 메뉴바 팝오버 · Dock 토글 · 로그인 자동 실행 토글 ·
  설정 창(일반/단축키/오버레이/태그 4탭) · 논리적 하루(DayBoundaryService) ·
  브리핑 패널(시작/웨이크/기준시각/⌥⌘T 트리거, 이월/보류/버리기) ·
  플로팅 오버레이(전체화면 위 표시, 드래그·위치 기억, 불투명도·클릭 동작·최대 개수 설정) ·
  빠른 추가(⌥⌘N Spotlight식) · 완료 히스토리 · 태그 관리 · 서브태스크
- 저장소: `TaskStore` 프로토콜 + Codable JSON 스토어
  (`~/Library/Application Support/AnhamDie/store.json`). SwiftData는 CLT 툴체인의
  매크로 부재로 미도입(§8 예정대로) — build-app.sh에 재도입 가드 있음
- 테스트 30개 전부 통과 (`swift test`)
- 1차 SPM 빌드·설치 완료: `Scripts/build-app.sh --install` →
  `~/Applications/AnhamDie.app` (실행 확인, 상주 동작)
- 위젯 소스 코드(`Widget/`)와 XcodeGen 스펙(`project.yml`),
  `Scripts/build-with-xcode.sh`(팀 자동 감지 포함) 작성 완료 — 빌드만 남음
- 최종 게이트 라운드 수정: 논리적 하루 경계 통과 시 열려 있는 UI(오버레이·메인 창·
  브리핑 패널·메뉴바 팝오버)가 실시간 재평가되도록 `AppSettings.currentLogicalDay`
  (관찰 대상) 도입 — TriggerService(경계 타이머/웨이크/잠금 해제/기준 시각 변경)가 갱신,
  각 뷰 body가 읽음. BriefingController.show()는 표시 직전 rootView 재설정으로 이중 보장.
  부수 수정: 잠금 중 `.dayBoundary` 트리거도 해제 시점까지 보류(브리핑 소진 방지),
  dueDate 쓰기 3곳을 '자정 날짜 키' 규약(scheduledDateValue)으로 정정,
  빠른 추가 Esc 모니터가 자기 패널로 향한 Esc만 소비하도록 제한.

### 남은 것

- **위젯 빌드 (2차)**: Xcode 26.6 설치는 확인됨(xcodebuild -version 정상).
  그러나 `security find-identity -v -p codesigning` 결과 유효 인증서 0개 →
  Xcode > Settings > Accounts에 Apple ID(무료 개인 팀) 추가 후
  `bash Scripts/build-with-xcode.sh --install` 실행. 절차 상세는 README「위젯 빌드」.
- 2차 빌드 후 App Group 마이그레이션 실측 (store.json이 그룹 컨테이너로 이동하는지)
- 1차 SPM 산출물은 KeyboardShortcuts 리소스 번들의 .app 루트 배치 제약으로
  codesign seal 검증 실패 → 로그인 자동 실행(SMAppService)이 로그인 시점에 조용히
  실패할 수 있음. 2차 산출물로 교체하면 해소 (build-app.sh 출력의 확인 절차 참고)

### 검증에서 미해결로 남은 이슈

- ~~[major] AppGroup.identifier의 `$(TeamIdentifierPrefix)` 확장 불확실~~
  → **하드닝 완료 (최종 게이트 라운드)**: `$(TeamIdentifierPrefix)`는 엔타이틀먼트
  처리에서만 치환이 보장되고 Info.plist 빌드설정 확장에서는 빈 문자열이 될 수 있어
  전면 제거. App Group ID의 소스 오브 트루스를 하나로 통일:
  - `Scripts/build-with-xcode.sh`가 감지한 팀 ID를 `local.xcconfig`에
    `ANHAM_TEAM_ID = <팀ID>` / `DEVELOPMENT_TEAM = $(ANHAM_TEAM_ID)`로 기록
    (기존 `DEVELOPMENT_TEAM` 직접 지정 파일은 자동 승격).
  - `project.yml`에 `ANHAM_APP_GROUP_ID = $(DEVELOPMENT_TEAM).com.splguyjr.anhamdie`
    정의 — `DEVELOPMENT_TEAM`은 Info.plist 확장과 엔타이틀먼트 처리 양쪽에서
    실제로 치환되는 빌드 설정이다.
  - Info.plist 키 `AnhamDieAppGroupIdentifier`(앱·위젯)와 앱/위젯 엔타이틀먼트의
    application-groups가 전부 `$(ANHAM_APP_GROUP_ID)` 하나로 확장된다.
  - `build-with-xcode.sh` 말미에 검증 자동 실행: 빌드 산출물의
    Info.plist(PlistBuddy) vs 앱/위젯 `codesign -d --entitlements` 그룹 값 3자 대조 +
    `TEAMID.com.splguyjr.anhamdie` 형식 검사, 불일치 시 exit 4.
  `xcodegen generate` 성공 확인됨. 실제 서명 빌드 검증은 Xcode에 Apple ID 로그인 후
  2차 빌드에서 스크립트가 자동 수행한다.
- ~~[major] 설정의 오버레이 '클릭 동작' 미구현~~ → **게이트 라운드에서 해결됨**:
  `OverlayClickAction`(즉시 완료 체크/메인 창 열기/무시)이 AppSettings·SettingsOverlayTab·
  OverlayView에 구현되어 있음.

---

## 10. v2 요구사항 (2026-07-23 확정 — 1차 사용 피드백 기반)

### 10.1 메인 창 전면 재설계 — 사이드바형 (Things 스타일)

- `NavigationSplitView`: 좌측 사이드바 = 스마트 뷰(**해야할 일 / 백로그 / 완료 / 캘린더**) + 태그 목록(색 점, 클릭 = 해당 태그로 필터된 동일 뷰)
- **"해야할 일" 기본 뷰**: 날짜별 섹션을 한 화면에서 쭉 스크롤 —
  `🔴 지난 할 일`(미완료 overdue·이월 대상) → `오늘 M/d` → `내일 M/d` → 이후 날짜들(scheduled·due 통합).
  섹션 헤더에 날짜·요일·개수. 오늘자는 브리핑/오버레이가 담당하니 메인은 **넓은 전체 조망** 중심
- 기존 4탭 체제 폐기, 완료 히스토리(날짜 그룹)·백로그는 사이드바 뷰로 이관

### 10.2 캘린더 뷰 — 월간 그리드 + 드래그

- 월간 그리드, 셀에 task 제목 1~2개 + "+N개", overdue 빨강
- 날짜 클릭 → 그 날 목록 패널(체크/편집 가능)
- task를 다른 날짜 셀로 **드래그 → scheduledDate 변경**
- 월 이동(←/→/오늘 버튼), 사이드바 "캘린더"로 진입

### 10.3 메인 창 접근성

- 글로벌 단축키 **⌥⌘M = 메인 창 열기/포커스** (KeyboardShortcuts `.openMain`, 설정 변경 가능)
- Dock 아이콘 클릭·앱 재실행 시 메인 창 표시 (`applicationShouldHandleReopen`)
- 오버레이 헤더 클릭 → 메인 창 열기 (클릭 동작 설정과 별개로 헤더는 항상)
- 메뉴바 팝오버 "메인 창 열기" 유지

### 10.4 위치·상태 기억

- **브리핑 패널도 드래그 이동 + 위치 저장/복원** (오버레이는 기존 유지)
- 재시작·재부팅 후 오버레이 표시 여부·위치, 브리핑 위치 그대로 복원

### 10.5 디자인 리프레시 — 가시성 중심

- `AppTheme` 단일 디자인 시스템: 타이포 스케일(크기·웨이트 대비 강화, 본문 상향), 고대비 텍스트 컬러, 섹션/행/배지 시각 계층 분명히, 여백·행 높이 재조정
- Scribble 미니멀은 유지하되 밋밋함 해소: 액센트 컬러, 호버 피드백, 우선순위·태그 점 가시성 상향

### 10.6 행 사용성 — 클릭-펼침 의존 제거

- **호버 인라인 액션**: 행 우측에 날짜/우선순위/태그/삭제 아이콘
- **우클릭 컨텍스트 메뉴**: 오늘로/내일로/날짜 선택/우선순위/태그/백로그로/삭제
- **키보드**: 행 선택 상태에서 ⌫ 삭제, ⌘1/2/3 우선순위, ⌘T 오늘로, ⌘D 내일로, Enter 상세
- **더블클릭 제목 = 인라인 편집**. 상세 펼침(메모/서브태스크)은 유지

### 10.7 마감일 원클릭

- `lastUsedDueDate` 기억 → 날짜 UI에 **[오늘] [내일] [최근: M/d] 원클릭 칩**, 달력은 최근 설정한 날짜의 달로 열림
- 연속 등록 시 직전 날짜를 딸깍 한 번으로 재사용

### 10.8 퀵애드 v2 — 토큰 + 버튼

- 실시간 토큰 파싱: `#태그`(자동완성·미존재 시 생성), `!높음/!낮음`, 날짜 자연어(오늘/내일/모레/M월 d일/M/d)
- 입력창 아래 칩 행: 파싱 결과 실시간 표시 + 클릭 수정, [최근 날짜]/[백로그] 버튼
- Enter 시 토큰 제거된 제목으로 저장

### 구현 노트

- v1 핵심 로직(논리적 하루·이월·브리핑·스토어) **회귀 금지** — 검증에 v1 회귀 차원 포함
- 토큰 파서·날짜 그룹핑·lastUsedDueDate 유닛 테스트 추가

### v2 구현 현황 (2026-07-23, 취합 게이트 기준)

#### 완료

- **§10.1 사이드바형 메인 창**: `NavigationSplitView` + 사이드바(해야할 일/백로그/완료/
  캘린더 스마트 뷰 + 태그 목록 색 점, 태그 클릭 = 필터). "해야할 일"은 날짜별 섹션
  단일 스크롤(`🔴 지난 할 일` → 오늘 → 내일 → 이후, scheduled·due 통합, 헤더에
  날짜·요일·개수). 기존 4탭 폐기, 완료 히스토리·백로그는 사이드바 뷰로 이관
- **§10.2 캘린더 뷰**: 월간 그리드(제목 1~2개 + "+N개", overdue 빨강), 날짜 클릭 →
  그 날 목록 패널(체크/편집), 셀 간 드래그로 scheduledDate 변경, ←/→/오늘 월 이동
- **§10.3 접근성**: ⌥⌘M(`.openMain`, 설정 재지정 가능) · Dock 클릭/재실행 시 메인 창
  (`applicationShouldHandleReopen`) · 오버레이 헤더 클릭 = 메인 창(클릭 동작 설정과 별개) ·
  메뉴바 팝오버 "메인 창 열기" 유지
- **§10.4 위치·상태 기억**: 브리핑 패널 드래그 이동 + 위치 저장/복원 추가.
  오버레이 표시 여부·위치는 재시작 후 복원(기존 유지)
- **§10.5 디자인 리프레시**: `AppTheme` 단일 디자인 시스템(타이포 스케일·고대비 텍스트·
  섹션/행/배지 계층·여백/행 높이·액센트·호버 피드백) — 메인/오버레이/브리핑/퀵애드/설정 적용
- **§10.6 행 사용성**: 호버 인라인 액션(날짜/우선순위/태그/삭제), 우클릭 컨텍스트 메뉴
  (상세·이름 편집·오늘로·내일로·날짜 선택·우선순위·태그·백로그로·삭제), 행 선택 키보드
  (⌫ 삭제, ⌘1/2/3 우선순위, ⌘T 오늘로, ⌘D 내일로, Enter 상세), 더블클릭 제목 인라인 편집.
  액션 로직은 `RowAction` 단일 소스로 통일
- **§10.7 마감일 원클릭**: `lastUsedDueDate` 기억, 날짜 UI 공용 `DueDateControls`에
  [오늘][내일][최근 M/d] 칩 + 달력(최근 날짜의 달로 열림)
- **§10.8 퀵애드 v2**: `QuickAddTokenParser`(순수 함수) — `#태그`(자동완성·공백 포함
  기존 태그명 최장일치·미존재 시 생성), `!높음/보통/낮음`(=!1/2/3), 날짜 자연어
  (오늘/내일/모레/M월 d일/M/d, 지난 날짜는 내년). 칩 행 실시간 표시 + 클릭 수정,
  [오늘][내일][최근][백로그] 빠른 버튼, Enter 시 토큰 제거 제목으로 저장
- **구현 노트**: 토큰 파서·날짜 그룹핑(`scheduleSections`)·lastUsedDueDate 유닛 테스트
  포함 **테스트 67개 전부 통과**(v1 30개 유지 — 회귀 없음). v1 핵심 로직(논리적 하루·
  이월·브리핑·스토어·오버레이) 회귀 검증 통과
- **취합 게이트**: `Scripts/build-app.sh --install` 재실행 → `~/Applications/AnhamDie.app`
  v2 설치본 교체·재실행·상주 확인. README v2 반영(사이드바·캘린더·행 단축키 표·
  퀵애드 토큰 문법·⌥⌘M)

#### 미해결 (v1에서 이어짐 — v2 신규 미해결 없음)

- **위젯 빌드(2차)**: Xcode는 있으나 코드서명 인증서 0개 — Xcode > Settings > Accounts에
  Apple ID(무료 개인 팀) 추가 후 `bash Scripts/build-with-xcode.sh --install`.
  이후 App Group 마이그레이션 실측 + 스크립트 말미의 그룹 ID 3자 대조 자동 검증 통과 확인
- 1차 SPM 설치본은 KeyboardShortcuts 리소스 번들 제약으로 codesign seal 검증 실패 —
  로그인 자동 실행(SMAppService)이 조용히 실패할 수 있음. 2차 산출물로 교체 시 해소

---

## 11. v3 요구사항 (2026-07-23 확정 — 2차 사용 피드백 기반)

### 11.1 캘린더 개선

- 날짜 패널의 task 제목 **잘림 제거** — 전체 표시(최대 2줄 줄바꿈, 그래도 넘치면 말줄임+툴팁)
- 캘린더 셀의 task 칩에 **호버 툴팁**으로 전체 제목 표시
- **"이 날 할 일 추가" 입력을 목록과 분리** — 패널 최하단 구분선 아래 별도 영역으로 이동

### 11.2 오버레이 클릭 규칙·리사이즈

- 클릭 규칙 고정(기존 '클릭 동작' 설정 제거):
  - **체크 원 클릭 = 완료 처리** (유예 애니메이션 §11.6)
  - **행(원 제외) 클릭 = 메인 창 열기**, **헤더 클릭 = 메인 창 열기**
- **자유 리사이즈**: NSPanel resizable, 최소/최대 제한, 크기 저장·복원. 제목은 폭에 맞춰 최대 2줄 줄바꿈
- 오버레이에서도 **행 드래그로 수동 정렬** (§11.3 공통 순서 반영). 창 이동은 헤더 드래그로만

### 11.3 정렬 규칙 통일

- **초기 배치**: 우선순위 높음 → 같으면 먼저 등록(createdAt 오름차순)으로 sortOrder 부여
- 이후 **드래그로 수동 정렬** (메인 리스트·오버레이 공통, sortOrder 영속) — 드래그 후에는 수동 순서가 우선
- 메인·오버레이·브리핑·위젯 모두 같은 순서로 표시 (스토어 정렬 API 단일화)

### 11.4 단축키 시스템 재정비 (IntelliJ 충돌 대응)

- **앱별 예외 목록**: 지정 앱이 활성(frontmost)일 때 전역 단축키 전체 자동 양보.
  기본값 = JetBrains 계열(`com.jetbrains.*`). 설정에서 실행 중 앱 선택/번들ID로 추가·제거
- **마스터 토글**: 전역 단축키 전체 on/off
- **개별 토글**: 단축키(브리핑/오버레이/퀵애드/메인 창)별 on/off + Recorder로 직접 지정(기존 유지, ⌥⌘M 포함 4개 전부)
- 설정 > 단축키 탭 재구성: 마스터 → 개별(토글+Recorder) → 예외 앱 목록 순

### 11.5 반복 작업

- 반복 규칙: **매일 / 평일 / 매주(요일 선택)**. 상세 뷰에서 설정, 행에 ↻ 배지
- 완료(또는 취소) 시 다음 발생일의 task 자동 생성 (제목·태그·우선순위·반복 규칙 승계, 서브태스크는 미완료 상태로 복제)
- 미완료로 하루가 지나면 일반 task처럼 이월 제안에 표시 — 버려도 다음 회차는 정상 생성
- JSON 스토어 스키마 버전 증가 + 마이그레이션 (version 검사 로직 있음 — 필수)

### 11.6 완료 애니메이션 + 유예

- 체크 시 애니메이션 → **1.5초 유지 후** 정리(오버레이·메인 리스트 공통), 유예 중 재클릭 = 완료 취소
- 오버레이에서 완료 즉시 사라지는 현상 제거

### 11.7 메인 창 상태 복원

- 메인 창 위치·크기·마지막 선택 사이드바 뷰 저장 → 재실행/재열기 시 복원

### 11.8 메인 인라인 추가에도 토큰

- 메인 창 인라인 추가 행에서 퀵애드와 동일한 토큰 문법(`#태그 !우선순위 날짜`) 지원 — QuickAddTokenParser 재사용, 입력 중 칩 미리보기

### 구현 노트

- v1·v2 회귀 금지 (특히 스토어 마이그레이션·논리적 하루·오버레이 동작) — 검증에 회귀 차원 포함
- 반복 생성 로직·정렬 규칙·마이그레이션 유닛 테스트 필수

### v3 구현 현황 (2026-07-23, 통합 게이트 기준)

#### 완료 — §11.1~§11.8 전부

- **§11.1 캘린더**: 날짜 패널 행 제목 최대 2줄+말줄임+툴팁(공용 MainTaskRow에
  Environment 기반 `taskRowTitleLineLimit` 도입 — 기본 1줄, 패널만 2 주입, 시그니처 불변),
  패널 헤더 제목 2줄+툴팁, 셀 칩 호버 툴팁, "이 날 할 일 추가"를 패널 최하단
  구분선 아래 고정 영역으로 분리
- **§11.2 오버레이**: 클릭 규칙 고정(체크 원=유예 완료 · 행/헤더=메인 창) —
  기존 '클릭 동작' 설정 UI·`OverlayClickAction`·`overlayClickAction` 잔재 완전 제거.
  자유 리사이즈(200×120~520×960, 크기 저장·복원), 제목 2줄 줄바꿈+툴팁,
  목록 스크롤("+N개" 절단 대체), 헤더 드래그=창 이동, 행 드래그=정렬
- **§11.3 정렬 단일화**: 초기 배치 = 우선순위 → createdAt(스토어 단일 API),
  메인·오버레이 행 드래그 수동 정렬(sortOrder 영속), 전 화면 동일 순서
- **§11.4 단축키**: 마스터 토글 → 개별 4개(토글+Recorder) → 예외 앱 목록
  (frontmost 접두사 매칭 자동 양보, 기본 `com.jetbrains.`, 실행 중 앱 선택/번들ID 추가)
- **§11.5 반복**: 매일/평일/매주(요일) — 상세 뷰 편집, ↻ 배지(메인·브리핑·퀵애드 칩),
  완료 유예 확정·이월 버리기 시 다음 발생 자동 생성(시리즈ID 중복 방지),
  문서 버전 1→2 마이그레이션(sortOrder 재부여 포함)
- **§11.6 완료 유예**: `CompletionGraceController` 단일 경로 — 체크 후 1.5초
  취소선 유지, 재클릭 취소, 오버레이·메인·브리핑 공통
- **§11.7 메인 창 상태**: 프레임·마지막 사이드바 선택 저장/복원
- **§11.8 메인 인라인 토큰**: 해야할 일·백로그 인라인 추가 행에
  QuickAddTokenParser 재사용 + 칩 미리보기

#### 통합 게이트 검증

- `swift build` / `swift test` 그린 — **테스트 111개**(v2 67 + v3 신규 44,
  마이그레이션 실측 테스트 포함), 잔여 경고는 QuickAddController NSEvent Sendable 기존 1건
- **마이그레이션 실측**: 실제 설치본의 v1 `store.json`(task 5건)을 v3 빌드로 로드 →
  전 항목 보존 + `version: 2` 재기록 + recurrence 키 부여 확인
  (실측 후 원복 — 설치본은 v2 앱이라 v1 문서 유지)
- `Scripts/build-app.sh --install`로 ~/Applications 설치본 교체 → 기존 프로세스
  pkill 후 새 산출물 재실행, 10초+ 생존 확인 후 상주 유지(로그인 자동 실행 seal
  제약은 §8 2차 Xcode 빌드로 해소)

#### 미해결 (v1·v2에서 이어짐 — v3 신규 미해결 없음)

- 위젯 빌드(2차): Xcode에 Apple ID(무료 개인 팀) 추가 후
  `bash Scripts/build-with-xcode.sh --install` — 이후 App Group 마이그레이션 실측
- 1차 SPM 산출물의 codesign seal 제약(로그인 자동 실행 영향)은 2차 산출물로 해소
- borderless+nonactivating 패널의 가장자리 드래그 리사이즈는 헤드리스 검증 불가 —
  실기 GUI에서 확인 권장

---

## 12. v4 요구사항 (2026-07-23 확정 — 캘린더 뷰·예정 리스트 개편)

### 12.1 캘린더 다중 뷰 (월/주/일)

- 상단에 뷰 전환 세그먼트: **월 / 주 / 일** (+ 기존 오늘·◀·▶ 이동은 현재 뷰 단위로 동작)
- **월간**(기존 개선): 셀 높이를 창 높이에 맞춰 키워 셀당 task 3~4개까지 표시(초과 "+N개"), 셀 task 칩 호버 툴팁
- **주간**: 일~토 7열, 각 열은 그날 task를 세로로 나열(스크롤), **열 간 드래그 = scheduledDate 변경**(자정 날짜 키 규약 준수), 오늘 열 강조
- **일간**: 그날 하나를 넓은 리스트로(우측 날짜 패널의 전체폭 확장판), 제목 전체 표시
- 선택 뷰 종류는 저장·복원(MainWindowState 또는 AppSettings)

### 12.2 캘린더 우측 날짜 패널 개선

- **패널 폭 드래그 조절**: 캘린더 본문과 우측 날짜 패널 사이 경계를 드래그해 좌우 폭 조절, 폭 저장·복원
- **패널 항목 제목 줄바꿈**: 폭과 무관하게 최대 2줄 줄바꿈(넘치면 말줄임+.help 툴팁) — 현재 가로 잘림(예: "PR 리...") 해소
- "이 날 할 일 추가"는 패널 하단 별도 영역 유지(§11.1)

### 12.3 사이드바 접기

- 좌측 사이드바 토글(상단 버튼/기존 사이드바 아이콘) — 접으면 캘린더·리스트에 더 넓은 가로 공간. 접힘 상태 저장·복원

### 12.4 "해야할 일" 뷰 예정 리스트 개편

- 섹션 구조를 **① 지난 할 일 · ② 오늘 · ③ 예정** 3개로 축소.
  기존처럼 내일/모레/개별 날짜를 **큰 섹션으로 쪼개지 않는다.**
- **③ 예정**은 내일 이후 전체를 **하나의 연속 리스트**로 묶되, 내부에 **가벼운 미니 날짜 구분선**(작은 라벨: "내일 7/24", "7/28 (월)" 등)으로 구분. 섹션 헤더가 아니라 리스트 내부 인라인 divider
- 정렬·완료 유예·행 UX(호버/우클릭/키보드)는 §11 그대로 승계

### 12.5 미래 날짜 추가 (내일 이후)

- **'예정' 리스트 상단에 추가행 하나** — 입력 시 기본 날짜 = 내일, `#태그 !우선순위 날짜` 토큰으로 임의 날짜 지정(QuickAddTokenParser 재사용, 예: "기획서 7/28")
- 날짜 토큰이 없으면 내일로, 있으면 해당 날짜로 scheduledDate 지정 후 적절한 미니 구분 위치에 삽입
- 현재 내일 이후 추가 불가 문제 해소

### 12.6 날짜 간 이동 (리스트에서)

- "해야할 일" 리스트에서 **task를 다른 날짜 미니 구분/섹션으로 드래그 = scheduledDate 변경** (지난→오늘, 오늘→예정 특정일 등). 같은 그룹 내 드래그는 수동 정렬(§11.3), 다른 그룹으로 드래그는 날짜 변경으로 해석
- 우클릭 메뉴의 오늘로/내일로/날짜 선택(§11.6)도 유지 — 드래그와 병행

### 12.7 재정렬 모션 개선

- 리스트 상하 재정렬 시 부자연스러운 점프 제거 → **부드러운 스왑 애니메이션**(SwiftUI transaction/animation, matchedGeometry 또는 목록 이동 애니메이션). 오버레이·메인 공통 적용
- 드래그 중 삽입 위치 인디케이터 표시

### 구현 노트

- v1~v3 회귀 금지(특히 정렬 영속·완료 유예·마이그레이션·논리적 하루). 검증에 회귀 차원 포함
- 날짜 간 드래그 = 날짜변경 vs 같은 그룹 = 수동정렬 분기 규칙, 예정 리스트 미니 구분 그룹핑, 캘린더 주/일 뷰 그룹핑 유닛 테스트 추가
- 스키마 변경 없음(모두 표시/상호작용 레이어) — 스토어 마이그레이션 불필요 예상

### v4 구현 현황 (2026-07-23, 취합 게이트 기준)

#### 완료 — §12.1~§12.7 전부

- **§12.1 캘린더 월/주/일**: 상단 세그먼트(월/주/일)로 뷰 전환, 오늘·◀·▶는 현재 뷰
  단위로 이동. 월간 셀 높이를 창 높이에 맞춰 키워 셀당 task 다수(초과 "+N개")·칩 호버
  툴팁, 주간 일~토 7열 세로 나열 + 열 간 드래그 reschedule(자정 날짜 키) + 오늘 열 강조,
  일간 전폭 단일일 리스트(제목 전체 표시). 선택 뷰 종류는 AppSettings에 저장·복원
  (`CalendarViewMode`)
- **§12.2 우측 날짜 패널**: 본문·패널 경계 드래그로 폭 조절(`calendarPanelWidth` 저장·복원),
  패널 행 제목 최대 2줄 줄바꿈+말줄임+.help(`taskRowTitleLineLimit=2` 주입) — 가로 잘림 해소.
  "이 날 할 일 추가"는 패널 하단 별도 영역 유지(§11.1)
- **§12.3 사이드바 접기**: `NavigationSplitView` columnVisibility 토글(접힘=.detailOnly),
  `sidebarCollapsed` 저장·복원 — 접으면 캘린더·리스트가 전폭 확보
- **§12.4 예정 리스트 개편**: "해야할 일"을 ①지난 ②오늘 ③예정 3섹션으로 축소.
  ③예정은 내일 이후 전체를 단일 연속 리스트(`todoSectionsV4`)로 묶고 각 날짜 그룹 첫
  항목에만 인라인 미니 구분선("내일 7/24"/"7/28 (월)")을 실음(섹션 헤더 아님).
  소속·정렬은 `scheduleSections` 단일 소스 재사용
- **§12.5 미래 날짜 추가**: 예정 리스트 상단 추가행(기본 날짜=내일), `#태그 !우선순위 날짜`
  토큰(QuickAddTokenParser 재사용)으로 임의 날짜 지정 — 내일 이후 추가 불가 해소
- **§12.6 날짜 간 이동**: "해야할 일" 리스트에서 다른 날짜 그룹으로 드래그 = `scheduledDate`
  변경, 같은 그룹 = 수동 정렬(§11.3). 순수 판정 `ScheduleDrag.action` + MainActor `apply`,
  그룹 소속은 `todoSectionsV4` 단일 소스. 우클릭 오늘로/내일로/날짜 선택 병행 유지
- **§12.7 재정렬 모션**: `sortOrder` 변화에만 반응하는 `reorderMotion`으로 부드러운 스왑,
  드롭 삽입 위치 인디케이터(`TaskReorderIndicator`) — 메인·오버레이 공통

#### 게이트 라운드 (v3 회귀 하드닝)

- **1R**: 행이 그룹 세로 공간 대부분을 차지하므로 '행 위' 드롭도 다른 날짜 그룹이면
  reschedule 경로로 흐르게(§12.6)
- **2R**: 예정 평탄화 시 scheduled∪due 이중 소속 태스크가 세 버킷/형제 ForEach에 걸쳐
  task.id가 중복되던 것 dedup — 순회 순서(지난→오늘→날짜 오름차순)로 "가장 이른 소속
  그룹" 한 곳에만 방출해 SwiftUI id 유일성 보장
- **3R**: §12.6 reschedule을 "해야할 일" 리스트로 한정(`taskRowReorderOnly` 환경값).
  캘린더 일간 뷰/패널·오버레이는 `reorderOnly=true`로 수동 정렬만 — 1R의 '행 위 드롭
  reschedule'이 이들 컨텍스트에서 cross-group 행 위 드롭을 silent reschedule로 만들던
  v3 회귀 차단(예: 캘린더 today 패널에 뜬 overdue 항목을 같은 패널 내로 드롭). "해야할 일"만
  environment 기본값 false를 써 §12.6 유지, `TaskReorderDropDelegate`는 기본 `reorderOnly=true`

#### 3R 게이트 검증

- `swift build` / `swift test` 그린 — **테스트 144개**(v3 111 유지 + v4 신규 33: 3섹션
  평탄화·cross-bucket dedup·주간 7열·일간 단일일·캘린더 뷰모드·레이아웃 상태·날짜 간
  드래그 규칙 유닛 테스트 포함, v1~v3 회귀 없음). 잔여 경고는 QuickAddController NSEvent
  Sendable 기존 1건(v3부터)
- `SCRATCH_PATH=… bash Scripts/build-app.sh`로 release 번들 조립 성공 →
  `dist/AnhamDie.app` 10초+ 스모크(비격리 직접 실행 11초 생존, 상주 확인).
  codesign seal 제약은 §8 1차 SPM 산출물의 알려진 구조적 제약(2차 Xcode 빌드로 해소)
- **스키마 변경 없음** — 모두 표시/상호작용 레이어. 스토어 마이그레이션 불필요(문서 version 2 유지)

#### 취합 게이트 검증 (최종)

- `Scripts/build-app.sh --install`로 release 번들 조립·설치 성공 →
  기존 프로세스 pkill 후 `~/Applications/AnhamDie.app` 재실행, 10초+ 생존·상주 확인.
  잔여 경고는 QuickAddController NSEvent Sendable 기존 1건(v3부터), codesign seal
  제약은 §8 1차 SPM 산출물의 알려진 구조적 제약(2차 Xcode 빌드로 해소)
- README v4 반영(캘린더 월/주/일·패널 폭 조절·사이드바 접기, 예정 3섹션·미래날짜
  추가행·날짜 간 드래그, 재정렬 스왑 모션+삽입 인디케이터)

#### 미해결 (v1~v3에서 이어짐 — v4 신규 미해결 없음)

- ~~**§12.6 cross-group reschedule 위치**: 델리게이트→apply 결선이 유닛 커버 밖~~
  → **해소 (2026-07-23, 커밋 후속)**: 3R 검증이 재신고한 "캘린더 일간 뷰/패널에서
  silent reschedule" major는 실제로는 이미 `.environment(\.taskRowReorderOnly, true)`
  주입(CalendarDayView·CalendarDayPanel)과 델리게이트 기본 `reorderOnly=true`,
  오버레이 직접 생성 기본값으로 막혀 있던 **false positive**였음(환경값 전파를
  추적하면 확인됨). 결선의 결정 로직을 `applyRowDrop(...)` 순수 헬퍼로 추출하고
  `RowDropRoutingTests`로 회귀 잠금: reorderOnly=true면 그룹 무관 정렬만(=일간 뷰/패널·
  오버레이 안전), false+다른 그룹만 reschedule, 완료(비활성) 소스는 reschedule 안 함.
  테스트 148개 그린.
- 위젯 빌드(2차): Xcode에 Apple ID(무료 개인 팀) 추가 후
  `bash Scripts/build-with-xcode.sh --install` — 이후 App Group 마이그레이션 실측
- 1차 SPM 산출물 codesign seal 제약(로그인 자동 실행 영향)은 2차 산출물로 해소
- borderless+nonactivating 패널 가장자리 리사이즈, 패널 폭 드래그·사이드바 접힘 등
  GUI 인터랙션은 헤드리스 검증 불가 — 실기 GUI 확인 권장

---

## 13. v5 요구사항 (2026-07-24 확정 — 사이드바 중복·색상 테마·이월 카운트·우선순위/태그 구분)

### 13.1 사이드바 토글 중복 제거

- 현재 `MainWindowView`가 커스텀 `sidebar.left` 버튼(§12.3)을 추가하면서 네이티브
  `.toolbar(removing: .sidebarToggle)`도 걸어 **토글이 2개** 보인다. **정확히 1개만** 남긴다.
- 접힘 상태 영속(`sidebarCollapsed` ↔ `columnVisibility` 동기화, §12.3)은 그대로 유지.
- 표준 macOS 사이드바 토글 하나로 통일하는 방향 권장(커스텀 버튼 제거 + 네이티브 유지 +
  `onChange(columnVisibility)`로 영속). 어느 쪽을 남기든 최종 결과는 토글 1개.

### 13.2 색상 테마 (프리셋 팔레트 + 강조색 피커)

- **동적 테마 시스템**: 현재 정적 `AppTheme.*` 색을 사용자 설정 기반으로 해석하도록 전환.
  모든 색 참조가 "현재 테마"에서 나오게 하고, 앱 전역 실시간 반영.
- **프리셋 팔레트**: 몇 가지 큐레이트 테마(예: 기본/세피아/다크/포레스트/모노) 중 선택.
  각 팔레트는 배경·표면·텍스트·구분선·기본 강조색 세트 정의.
- **강조색 ColorPicker**: 팔레트와 별개로 강조색을 직접 지정(액센트·선택·인디케이터 등에 반영).
- 설정에 **'테마' 탭/섹션** 신설: 프리셋 갤러리(썸네일) + 강조색 피커, 변경 즉시 적용.
- 선택 팔레트·강조색을 AppSettings에 영속. Due 색상 규칙(지남/오늘/임박/여유)은
  테마 안에서 재정의 가능하되 의미(빨강/주황/노랑/회색 계열)는 유지.
- 라이트/다크 대응 유지, 가시성(대비) 기준 준수(§10.5).

### 13.3 이월(↺) 카운트 정리

- **백로그→오늘 이동은 이월로 치지 않는다**: `RolloverService.moveToBacklog`에서
  `rolloverCount = 0`으로 리셋(백로그 항목은 '미룬 날'이 없으므로 이월 이력 없음).
- 이로써 백로그에서 오늘로 가져온 태스크에는 ↺ 배지가 뜨지 않는다.
- 진짜 이월(이전 예정일 미완료 → 브리핑 '오늘로 가져오기')만 `rolloverToToday`에서 카운트.
  모든 '오늘로'/드래그/'내일로' 등 일반 재배정 경로는 카운트를 올리지 않음(현행 유지 확인).

### 13.4 우선순위/태그 시각 구분

- 현재 우선순위 점과 태그 점이 **둘 다 원**이라 구별 불가. 다음으로 전환:
  - **우선순위 = 행 왼쪽 세로 색 막대**: 높음=빨강, 보통=중립(예: 얇은 회색/미표시),
    낮음=흐림 등 굵기·색으로 구분(테마 색 사용). 행 리딩 엣지에 배치.
  - **태그 = 글자 칩(TagPill)**: 태그명 텍스트 + 태그 색 배경/테두리의 작은 버튼형 칩.
    행 트레일링에 나열, 넘치면 "+N". 색점 방식 제거.
- 적용 범위: 메인 리스트 행(MainTaskRow), 오버레이 행, 캘린더 일간 뷰/날짜 패널 행,
  상세 뷰. 공용 컴포넌트(TagPill, PriorityBar)로 통일.
- 캘린더 월간/주간 셀의 좁은 칩은 간소화 허용(우선순위 색 테두리/점 대체 가능) — 단 리스트
  계열은 위 규칙 준수.

### 구현 노트

- v1~v4 회귀 금지. 특히 테마 전환은 전 화면 색 참조를 건드리므로 회귀 위험 큼 —
  검증에 '색 참조 누락(하드코딩 잔재)·다크모드·대비' 차원 포함.
- 팔레트 해석·강조색 반영·rolloverCount 리셋·태그칩 오버플로 유닛/스냅샷 테스트 추가.
- 스키마: 태그·우선순위 데이터 모델 불변(표시 레이어만). 테마 설정은 AppSettings에 추가(마이그레이션 불필요).

### v5 구현 현황 (2026-07-24, 취합 게이트 기준)

#### 완료 — §13.1~§13.4 전부

- **§13.1 사이드바 토글 중복 제거**: `MainWindowView`의 커스텀 `sidebar.left` 버튼과
  `toggleSidebar()`를 제거하고 **표준 macOS 사이드바 토글 하나로 통일**. `.toolbar(removing:
  .sidebarToggle)`을 걷어내 네이티브 토글을 되살리고, `onChange(columnVisibility)`가 접힘
  상태(`sidebarCollapsed`)를 그대로 영속(§12.3 유지). 최종 토글 1개.
- **§13.2 색상 테마**: 정적 `AppTheme.*` 색을 **동적 팔레트 해석**으로 전환.
  `ThemePalette`(기본/세피아/다크/포레스트/모노 — 배경·표면·텍스트·구분선·기본 강조색 세트),
  `ThemeManager`(선택 팔레트 + 강조색 오버라이드 결합), `AppTheme`은 현재 테마에서 색을
  해석. 설정 「테마」 탭(`SettingsThemeTab`)에 프리셋 갤러리 + 강조색 `ColorPicker`(비우면
  팔레트 기본) 신설, 변경 즉시 전역 반영. `selectedThemeID`·`accentColorHex`만 AppSettings에
  영속(스키마 마이그레이션 불필요). 전 화면(메인·오버레이·브리핑·캘린더·퀵애드·메뉴바·상세)
  색 참조를 팔레트 경유로 교체, 하드코딩 색 제거. Due 색 규칙 의미(빨강/주황/노랑/회색) 유지.
- **§13.3 이월 카운트 정리**: `RolloverService.moveToBacklog`가 `scheduledDate=nil`과 함께
  `rolloverCount=0`으로 리셋. 진짜 이월(`rolloverToToday`)만 카운트 +1, 일반 재배정은 불변.
- **§13.4 우선순위/태그 시각 구분**: 공용 컴포넌트 `PriorityBar`(행 리딩 세로 색 막대 —
  높음=빨강/보통=중립 얇은 회색/낮음=흐림)와 `TagPill`(태그명 글자 칩, 트레일링 나열 "+N")
  로 통일. MainTaskRow·오버레이·캘린더 일간/패널·상세 뷰가 동일 컴포넌트 사용, 우선순위/태그
  색 점 방식 폐기.

#### 게이트 라운드 (§13.3 백로그 불변식 하드닝)

- **1R**: UI 백로그 경로(`RowAction.moveToBacklog`)도 `rolloverCount=0` 리셋 + 회귀 잠금.
- **2R**: 백로그 진입 세 번째 쓰기 지점(우클릭 컨텍스트 메뉴 `RowActionsContextMenu`) 봉인 +
  캘린더 요일색 동적 테마화.
- **3R**: 백로그 진입 **네 번째** 쓰기 지점 봉인 — **행 날짜 팝오버의 '지우기'(nil)**.
  `MainTaskRow.scheduledDateBinding`의 setter가 `scheduledDate`만 nil로 두어 `rolloverCount`가
  남던 누수를, `RowAction.moveToBacklog`로 위임해 다른 세 경로와 동일하게 봉인(→ 백로그에서
  오늘로 가져와도 ↺ 배지 없음).

#### 취합 게이트 검증

- `swift test` 그린 — **테스트 167개**(v4 148 + v5 신규 19: 팔레트/강조색 결합
  `ThemeTests`·`RowActionsTests`(백로그 4경로 rolloverCount 리셋)·`RolloverServiceTests`
  이월 카운트 유닛 포함, v1~v4 회귀 없음). 잔여 경고는 QuickAddController NSEvent Sendable
  기존 1건(v3부터).
- `Scripts/build-app.sh --install`로 release 번들 조립·설치 성공 → 기존 프로세스 pkill 후
  `~/Applications/AnhamDie.app` 재실행·상주 확인. codesign seal 제약은 §8 1차 SPM 산출물의
  알려진 구조적 제약(2차 Xcode 빌드로 해소).
- README v5 반영(색상 테마·강조색, 우선순위 막대/태그 칩, 사이드바 단일 토글, 이월 카운트 정리).

#### 미해결 (v5 신규 미해결 없음)

- ~~**§13.3 백로그 불변식 누수 — 행 날짜 팝오버 '지우기'**~~ → **해소 (3R 게이트)**: 위 참조.
- GUI 인터랙션(테마 실시간 전환의 다크모드·대비, 팔레트 썸네일, 사이드바 접힘)은 헤드리스
  검증 불가 — 실기 GUI 확인 권장.
- 위젯 빌드(2차)·1차 SPM codesign seal 제약은 v4에서 이어짐(2차 Xcode 산출물로 해소).

---

## 14. v6 결정 (2026-07-24) — 위젯 제외·Homebrew 배포

- **위젯(M5) 최종 제외**: 플로팅 오버레이가 "상시 확인+바로 체크" 역할을 대체해 중복.
  `Widget/` 코드·`build-with-xcode.sh` 경로는 선택사항으로 저장소에 잔존 (README 참고).
  이로써 유료 Apple 개발자 계정 없이 전체 기능 배포 가능.
- **Homebrew 배포 (소스 빌드 formula)**: MIT 라이선스 추가, 저장소 공개(public) 전환,
  `v1.0.0` 태그. `splguyjr/homebrew-tap`의 `Formula/anhamdie.rb`가 소스를 받아
  로컬 빌드(CLT만 필요, 로컬 빌드라 Gatekeeper 격리 없음) 후 prefix에 .app 설치.
  사용자: `brew install splguyjr/tap/anhamdie`.
- 알려진 제약 승계: SPM 산출물의 KeyboardShortcuts 리소스 번들 위치로 인해 로그인
  자동 실행(SMAppService)이 조용히 실패할 수 있음 (문서화됨).

---

## 15. v7 요구사항 (2026-07-27 확정 — 테마 세분화·프리셋 차별화·v1.1.0 릴리즈)

### 15.1 사용자 커스텀 테마 (저장형, 전체 슬롯 편집)

- **CustomTheme**: id(UUID)·이름·isDark·12색 슬롯(배경/표면/보조표면/텍스트 기본·보조·비활성/구분선/강조/지남/오늘/임박/여유) — hex로 AppSettings(JSON 배열)에 영속. 여러 개 저장.
- **생성 흐름**: 갤러리에서 프리셋(또는 기존 커스텀)을 "복제해서 편집" → 이름 지정.
- **편집기**: 12슬롯 각각 ColorPicker, 슬롯별 ↺ 리셋(베이스 프리셋 값), 이름 변경·복제·삭제, isDark 토글. 편집 중 실시간 전역 반영.
- **선택**: selectedThemeID가 프리셋 id·커스텀 UUID 모두 지칭. 저장된 커스텀이 삭제되면 기본 프리셋 폴백. 기존 강조색 간이 오버라이드는 프리셋 선택 시 기능 유지(회귀 금지).
- 설정 > 테마 탭 구성: 프리셋 갤러리 → 내 테마 섹션(+ 새 테마) → 편집기.

### 15.2 모노 재설계 — 진짜 무채색

- 모노 = **UI 전체 회색조**(배경·강조·D-day 배지·우선순위 막대·태그 칩 등 크롬 전부), **overdue 빨강만 유지**(위험 신호). dueToday/dueSoon/dueRelaxed는 무채 농도로 구분.
- 팔레트에 `monochrome` 플래그 추가 — 이 플래그가 켜지면 태그 칩(사용자 지정 색 데이터)과 우선순위 막대도 무채 렌더(막대는 농도·두께로 높음/보통/낮음 구분, 칩은 테두리+글자 회색조). 적용 범위: 메인·오버레이·브리핑·메뉴바·캘린더 전부.

### 15.3 프리셋 추가·차별화 (총 9개)

- 추가 4종: **오션**(블루그레이 라이트+딥블루 강조) · **라벤더**(연보라+바이올렛) ·
  **미드나잇**(순흑 배경 다크, 기존 다크보다 깊게) · **하이콘트라스트**(순백/순흑/굵은 구분선, 접근성 중심).
- 기존 5종 포함 **모든 프리셋이 배경·표면 수준에서 육안 구분**되도록 색값 재점검(특히 기본 vs 모노 문제 재발 금지). 갤러리 썸네일이 배경/표면/강조/텍스트를 함께 보여주게 개선.

### 15.4 릴리즈 (완료 후)

- 앱 버전 1.1.0 (CFBundleShortVersionString), v1.1.0 태그+GitHub release,
  homebrew-tap `Casks/anhamdie.rb` version·sha256 갱신, `brew install` 실측 검증.

### 구현 노트

- v1~v6 회귀 금지. 테마 해석 경로(ThemeManager) 변경이 전 화면에 걸침 — 검증에 대비·차별화·커스텀 영속(JSON 왕복) 차원 포함.
- 커스텀 테마 인코딩/디코딩·hex 왕복·삭제 폴백·모노 무채 렌더 유닛 테스트 추가.

### v7 구현 현황 (2026-07-27, 3R 게이트 기준)

#### 완료 — §15.1~§15.3 전부 + §15.4 저장소 내 버전 반영

- **§15.1 사용자 커스텀 테마**: `CustomTheme`(UUID·이름·isDark·baseThemeID + 12색 hex 슬롯,
  Codable) + `ThemeColorSlot`(12슬롯 열거 — 편집기·리셋·썸네일 공유 계약).
  `AppSettings.customThemes`에 JSON 배열(Data)로 영속(빈 목록은 키 제거), CRUD는
  배열 재대입 경유(@Observable didSet). `ThemeManager.resolvedPalette(for:)`가
  selectedThemeID를 단일 진입점에서 해석 — 프리셋 id(비-UUID)와 커스텀 UUID 이름공간
  분리, 미상/삭제 id는 기본 프리셋 폴백, 파싱 실패 슬롯은 베이스 프리셋 값 폴백.
  선택 중 커스텀 삭제 시 selectedThemeID 기본 프리셋 폴백. 프리셋 선택 시 강조색 간이
  오버라이드는 v5 그대로(회귀 금지), 커스텀 선택 중엔 accent 슬롯이 우선(오버라이드 무시).
  설정 「테마」 탭: ① 프리셋 갤러리 9종 → ② 강조색 피커 → ③ 내 테마(+ 새 테마 =
  선택 테마 복제, 행별 복제·삭제) → ④ `ThemeEditorView`(12슬롯 ColorPicker + 슬롯별 ↺
  베이스 프리셋 리셋 + 이름 변경·isDark 토글, 편집 즉시 전역 반영).
- **§15.2 모노 재설계**: `ThemePalette.monochrome` 플래그(기본 false — 프리셋 이니셜라이저
  시그니처 불변, 커스텀은 항상 false). 모노 팔레트 전 슬롯 R=G=B, overdue만 빨강 유지.
  무채 렌더 계약은 `ThemeManager.resolvedTagColor(hex:)`(모노면 사용자 태그색 무시 →
  textSecondary)·`resolvedPriorityStyle(_:)`(모노면 농도+폭 4/3/2pt로 높음/보통/낮음) —
  메인·오버레이·브리핑·메뉴바·캘린더가 공용 경유. D-day는 무채 3단 농도(0.24/0.40/0.50).
  1R: 캘린더 요일 관례색(일=overdue 재사용·토=파랑)도 모노에선 textPrimary로 흡수 —
  회색조 UI에 요일 빨강이 남으면 overdue 위험 신호와 구분 불가(`CalendarPalette`에
  palette 주입 오버로드 추가, 비모노 프리셋은 기존 동작 회귀 잠금).
- **§15.3 프리셋 9종·차별화**: 추가 4종 — 오션(블루그레이+딥블루)·라벤더(연보라+바이올렛)·
  미드나잇(배경 0.02 순흑계 딥 다크)·하이콘트라스트(순백/순흑/짙은 구분선). 배경 명도·채널
  분포로 9종 전부 육안 구분(기본 0.95 쿨 / 모노 0.90 무채 / 하이콘트라스트 1.0 순백 /
  다크 0.11 / 미드나잇 0.02 …). 갤러리 썸네일이 배경/표면/강조/텍스트를 축소 카드+4색
  스트립으로 동시 노출. 1R: 유채 라이트 5종의 dueToday/dueSoon/dueRelaxed가 11pt 배지
  기준 2.3~3.2:1로 WCAG AA 미달이던 것을 의미(주황/황토/회백)를 유지한 채 어둡게 보정
  (표면 5.5:1+·배지 캡슐 4.5:1+), 모노 due 사다리도 0.44/0.62 → 0.40/0.50으로 보정
  (여유 슬롯 대형텍스트 3:1 하한 확보).
- **§15.4 (저장소 내)**: `Scripts/build-app.sh`·`project.yml`의 앱 버전 0.1.0 → **1.1.0**
  (CFBundleVersion/CURRENT_PROJECT_VERSION 2). v1.1.0 태그·GitHub release·homebrew-tap
  `Casks/anhamdie.rb` version/sha256 갱신·`brew install` 실측은 릴리즈 절차로 잔여(아래).

#### 게이트 라운드 (2R — 모노 강조색 봉인·하이콘트라스트 due 대비)

- **모노 무채 규칙을 accent까지 봉인**: `ThemeManager.accent`가 monochrome 팔레트에서는
  유채 `accentColorHex` 오버라이드를 무시하고 팔레트 무채 accent를 쓴다 —
  `resolvedTagColor`(사용자 유채 태그색 흡수)와 동일한 §15.2 규칙. 1R까지는 모노 선택 중에도
  저장된 유채 오버라이드가 강조색으로 새어 "빨강은 overdue 전용" 계약이 깨졌다.
  오버라이드 값 자체는 보존되어 비모노 프리셋 복귀 시 재적용(§15.1 회귀 금지, 테스트 잠금).
- **설정 UI 정합**: 모노 선택 중 강조색 섹션(피커·기본값 버튼) 비활성 — 무시될 값을 새로
  설정할 수 없게 하고, 상태 라벨·푸터가 이유(무채 규칙·보존 후 재적용)를 안내.
- **하이콘트라스트 due 대비 역전 해소**: dueToday/dueSoon이 11pt 배지 캡슐 기준
  3.97/4.47:1로 '접근성 중심' 프리셋인데 기본(4.53:1)보다 낮았다 → (0.62,0.29,0)/(0.48,0.37,0)
  으로 보정해 캡슐 4.97/4.99:1·표면 6.1:1 (주황/황토 의미 유지, 실측 재검증).

#### 게이트 라운드 (3R — overdue 대비 AA·중립 캡슐 관례·대비 잠금 테스트)

- **overdue도 due 3슬롯과 같은 AA 기준으로 재점검**: 1R이 dueToday/dueSoon/dueRelaxed만
  보정하고 overdue는 남겨 7프리셋에서 11pt 배지 캡슐(색 14% 블렌드) 3.40~3.81:1로 미달이었다
  → 빨강 의미(R 우세) 유지한 채 라이트 5종+모노는 어둡게·다크는 밝게 보정. 9프리셋 전부
  캡슐 4.53:1+·표면 5.78:1+ (미드나잇·하이콘트라스트는 기존 값이 이미 충족, 모노는
  monoKeepsOverdueRed의 R−G·R−B ≥ 40/255 계약 유지).
- **중립 캡슐 채움에 divider 재사용 금지**: 하이콘트라스트의 divider는 '굵은 구분선' 목적의
  근흑(0.10)이라 채움으로 쓰면 textSecondary(0.12) 글자와 겹친다(이월 배지 1.79:1, "+N" 칩
  3.6:1). 글자가 올라가는 중립 캡슐 5곳(이월 배지·캘린더 일간/날짜 패널·섹션 헤더 카운트
  배지·태그 "+N" 칩)을 **글자색 12% 틴트 채움 관례**로 통일 — 어떤 팔레트(커스텀 포함)에서도
  글자-채움 대비가 글자-표면 대비를 따라간다(9종 실측 4.93~12.98:1, D-day 14% 캡슐과 동일
  관례). 상세 뷰의 divider 0.5 채움 3곳은 하이콘트라스트에서도 4.96:1+라 유지.
- **대비 잠금 테스트 신설**(`ThemeContrastTests`): 주석 실측치가 아니라 WCAG 상대휘도 계산
  자체를 테스트로 고정 — ① overdue 표면 5.5:1+·캡슐 4.5:1+ ② textSecondary 12% 틴트 캡슐
  4.5:1+(표면·배경·보조표면) ③ due 사다리(today 캡슐 4.5+·soon 캡슐 4.5+/모노 표면 4.5+·
  relaxed 캡슐 3.0+). 이후 팔레트 색값 수정 시 대비 회귀가 즉시 레드.

#### 3R 게이트 검증

- `swift test` 그린 — **테스트 196개**(v6 167 + v7 신규 29: `CustomThemeTests` hex/JSON
  왕복·슬롯 리셋·복제·삭제 폴백·해석 이름공간, `MonochromeContractTests` 태그/우선순위/
  요일색/강조색 무채 계약 + 비모노 회귀 잠금, ThemeManager 커스텀 해석·강조색 오버라이드
  회귀, 3R `ThemeContrastTests` overdue/중립 캡슐/due 사다리 대비 잠금 3).
  잔여 경고는 QuickAddController NSEvent Sendable 기존 1건(v3부터).
- `Scripts/build-app.sh --install`로 release 번들(1.1.0) 조립·설치 성공 → 기존 프로세스
  pkill 후 `~/Applications/AnhamDie.app` 재실행, 10초 상주 스모크 그린. codesign seal
  제약은 §8 1차 SPM 산출물의 알려진 구조적 제약(2차 Xcode 빌드로 해소).
- README v7 반영(프리셋 9종·커스텀 테마 편집기·모노 무채 렌더).

#### 미해결 (v7)

- **§15.4 릴리즈 잔여**: `git push` + v1.1.0 태그 + GitHub release 발행,
  `splguyjr/homebrew-tap`의 `Casks/anhamdie.rb` version·sha256 갱신, `brew install`
  실측 검증 — 원격 푸시·별도 저장소 작업이라 릴리즈 절차에서 수행.
- GUI 인터랙션(커스텀 편집기 실시간 반영·썸네일 렌더·모노 전환 대비)은 헤드리스 검증
  불가 — 실기 GUI 확인 권장.

## 16. 에너지 최적화 (v1.1.1)

### 16.1 증상

- 사용자 배터리 소모 체감 보고. v1.1.0 설치본 사전 실측(유휴): CPU 평균 ~0.1%로 낮으나
  **유휴 웨이크업 ~26회/초**, RSS 144MB.
- 앱 코드에는 반복 타이머 없음(경계 단발 Timer, 1.5초 유예 `Task.sleep`, 일회성
  `asyncAfter`뿐) → 초기에는 프레임워크 레이어(오버레이 NSPanel `.ultraThinMaterial`,
  `@Observable` 재렌더, MenuBarExtra) 의심.

### 16.2 진단 (읽기·실행·측정만, 수치 근거)

앱 코드 감사 + `top -stats pid,cpu,idlew,power`(1초×13샘플, 앞 3개 버림, 10샘플 중앙값,
3회 반복) + `sample` 콜그래프 + `lsof`/저장 로그로 아래 낭비를 특정했다.

1. **no-op 크로스프로세스 알림 → 전량 재디코드·전 표면 재평가**: 위젯 변경 Darwin 알림
   수신 시 `TaskStore.mergeFromDisk`가 디스크 미변경이어도 store.json **전체 JSON 디코드**
   (실측 0.7ms/회, no-op 버스트 100회 = 100회 디코드) 후 `status` 등을 무조건 대입 —
   Observation은 등가 비교가 없어 no-op 대입도 알림을 쏘고 모든 관찰 표면 body가 재평가된다.
2. **저장 디바운스 결함**: `saveScheduled` 불리언 방식이라 스테일 `asyncAfter` 블록이
   잔존해 유효 간격이 0.5s보다 짧아짐 — 실측 20변경/2초에 **저장 7회**(기대 1회, 회당
   전체 JSON 인코드 + 디스크 쓰기 + onDidSave 후속).
3. **의미 없는 위젯 리로드 XPC**: App Group 엔타이틀먼트가 없는 SPM/ad-hoc(brew) 빌드는
   위젯이 store를 볼 수 없는데도 저장·경계변경마다 `WidgetCenter.reloadAllTimelines()`
   크로스프로세스 XPC 호출.
4. **앱 전환마다 핫키 전체 refresh**: frontmost 변경 알림마다 suspend 값이 안 바뀌어도
   `refresh()` — UserDefaults 읽기 + JSONDecoder 생성 + enable/disable로 **전환당 ~9.7ms**.
5. **드래그 중 UserDefaults 연타**: 오버레이 헤더 드래그 시 매 `mouseDragged`마다
   `overlayPosition` 좌표 2회(x·y) 쓰기.
6. **경계 단발 Timer tolerance 미지정**: 분 단위 정밀도면 충분한데 코얼레싱 불허 상태.
7. **BTM stale 등록**: 과거 `dist/` 경로가 로그인 항목으로 남아 재로그인 시 엉뚱한 번들
   실행 가능(등록 URL과 현재 번들 불일치).

### 16.3 수정 내역 (커밋 d8a32f7, 기능·시각 회귀 없음 — 테스트 197개 그린)

- `TaskStore.mergeFromDisk`: store.json **mtime 비교로 미변경 시 디코드 스킵**(no-op
  버스트 100회 → 디코드 1회) + 필드 **값 등가 비교 후에만 대입**(무의미한 Observation
  알림 차단). 회귀 잠금 테스트 1개 추가.
- 저장 디바운스: 불리언 → **`DispatchWorkItem` 보관 + cancel() 재예약**으로 트레일링
  디바운스 확립(20변경/2초 저장 7회 → **1회**).
- `AppContext`: App Group 없는 빌드에서 위젯 리로드 XPC 생략(저장·경계변경 경로 양쪽).
- `HotkeyService`: 앱 전환 시 suspend 값이 **실제로 바뀔 때만** refresh()(전환당 ~9.7ms → 0).
- `TriggerService`: 경계 단발 Timer `tolerance = 60s`(타이머 코얼레싱 허용).
- `OverlayController`/`OverlayView`: 위치 저장을 드래그 종료(mouseUp) **1회**로 축소.
- `App.reconcileLaunchAtLogin`: BTM 등록 경로가 현재 번들과 다르면 unregister 후 재등록.
- 버전 1.1.1 (CFBundleVersion 3) — `Scripts/build-app.sh`·`project.yml` 갱신,
  `build-app.sh --install`로 `~/Applications/AnhamDie.app` 교체·재실행.

### 16.4 전후 비교 (유휴, top 1초×10샘플 중앙값 ×3회)

| 항목 | v1.1.0 (사전 실측) | v1.1.1 (실측) |
|---|---|---|
| 유휴 웨이크업 | ~26회/초 | **0회/초** (오버레이 숨김·표시 각 3회 전부 중앙값 0) |
| 유휴 CPU | ~0.1% | **0.0%** (3회 전부 중앙값 0.0) |
| RSS | 144MB | **72~81MB** (숨김 71.8MB / 오버레이 표시 81.2MB — 재실행 직후 유휴 기준) |
| no-op 위젯 알림 100회 | JSON 디코드 100회 (0.7ms/회) | 디코드 **1회** (mtime 스킵) |
| 20변경/2초 저장 횟수 | 7회 | **1회** |
| 앱 전환당 핫키 refresh | ~9.7ms | 0ms (suspend 변화 없을 때) |
| 오버레이 드래그 좌표 저장 | 매 mouseDragged 2회 | 드래그 종료 시 1회 |

주의: RSS 전후는 세션 길이 조건이 다르다(사전 실측은 장기 상주 후, 사후는 재실행 직후
유휴) — 장기 상주 시 재상승 여부는 아래 관찰 항목.

### 16.5 남은 관찰 항목

- **~26회/초의 정확한 재현 조건 미확정**: 수정 후 오버레이 숨김/표시 두 상태 모두 0회/초로
  사전 실측을 재현할 수 없었다. 메인 창 열림 상태·장기 상주·OS 상태(디스플레이 절전 등)
  조합에서 재발하는지 며칠 상주하며 `top -stats idlew`로 추적 필요.
- **장기 상주 RSS 추이**: 재실행 직후 72~81MB → 수일 상주 후 144MB 수준으로 복귀하는지
  관찰(누수 vs 캐시 구분은 `footprint`/`leaks`로).
- **App Group 서명 빌드**: Xcode 서명 빌드에서는 위젯 리로드가 다시 활성화되는 경로 —
  해당 빌드로 배포 시 저장당 XPC 1회가 남는 것이 의도된 동작인지 재확인.
- **BTM 재등록 실측**: 재로그인 1회 실측으로 설치본 경로가 실행되는지 확인
  (`sudo sfltool dumpbtm`).
- §15.4 릴리즈 잔여(태그·GitHub release·cask 갱신)는 v1.1.1 기준으로 수행.

---

## 17. v8 요구사항 (2026-08-03 확정 — 메모 미리보기)

- **행 아래 메모 미리보기 한 줄**: 메모가 있는 task는 제목 아래 작은 보조 텍스트로
  메모 첫 줄 표시(1줄 말줄임, 테마 textSecondary·rowMeta 타이포). 메모 없으면 행 높이 불변.
- **적용 범위**: 메인 리스트 계열(해야할 일/백로그/완료)과 **브리핑 패널**만.
  오버레이·캘린더 날짜 패널/일간 뷰는 **제외**(밀도 유지) — MainTaskRow가 공용이므로
  환경값 방식(taskRowTitleLineLimit 선례)으로 컨텍스트별 opt-in.
- **설정**: 설정 > 일반에 "메모 미리보기 표시" 토글(기본 켬).
- 상세 펼침의 메모 편집은 기존 유지. 미리보기 줄 클릭은 행 클릭과 동일(선택/펼침).
- 회귀 금지: 행 높이 변화가 드래그 정렬 드롭 판정(rowHeight 기반)·완료 유예 표시를 깨지 않는지 확인.

### v8 구현 현황 (2026-08-03, 취합 게이트 기준)

#### 완료 — §17 전부 + 릴리즈 저장소 내 반영

- **미리보기 렌더** (커밋 c374413): `NotePreview.firstLine` 순수 헬퍼(개행 분리 → 선행
  빈 줄 건너뛰고 첫 '내용 있는' 줄 트리밍, 없으면 nil) — 메인 행·브리핑 행이 공유하는
  단일 추출 경로. `MainTaskRow.titleColumn`이 제목 아래 rowMeta·textSecondary 1줄
  말줄임으로 그린다. nil이면 뷰 자체를 만들지 않아 메모 없는 행의 높이 불변.
  메모 있는 행의 늘어난 높이도 드롭 절반 판정에 안전 — rowHeight는 헤더 전체의
  onGeometryChange 실측(미리보기 포함)이라 판정 기준이 실제 높이를 따라간다.
  완료/유예 중(displayCompleted)엔 진행률 메타 줄과 동일하게 색만 textDisabled로
  죽인다(취소선은 제목 전용 — 1R 코스메틱, 커밋 c0e164f).
- **적용 범위(opt-in)**: 환경값 `taskRowShowsNotePreview`(기본 false —
  taskRowTitleLineLimit·taskRowReorderOnly 선례) 신설, 해야할 일(ScheduleListView)/
  백로그/완료 컨테이너만 true 주입. 오버레이·캘린더 날짜 패널/일간 뷰는 미주입으로
  자연 비활성(밀도 유지, 코드 변경 0). BriefingView는 자체 레이아웃 관례대로 오늘
  목록·이월 제안 행에 동일 스타일(rowMeta·textSecondary·1줄)을 직접 그린다
  (설정 토글만 따름 — 브리핑은 §17 적용 대상이므로 opt-in 환경값 불필요).
- **설정**: `AppSettings.showNotePreview`(기본 켬, UserDefaults 영속, 미설정 시 true
  폴백) + 설정 > 일반 「메모 미리보기 표시」 토글. 컨테이너 opt-in과 AND — 끄면
  메인·브리핑 전 구역에서 즉시 숨김.
- **릴리즈(저장소 내)**: 앱 버전 1.1.1 → **1.2.0**(CFBundleVersion/
  CURRENT_PROJECT_VERSION 4) — `Scripts/build-app.sh`·`project.yml` 동기.
  README v8 반영(기능 목록 「메모 미리보기 (v8)」·설정 항목 일반 탭).

#### 게이트 검증

- `swift test` 그린 — **테스트 204개**(v1.1.1 197 + v8 신규 7: `NotePreviewTests` —
  설정 기본값 켬/라운드트립, firstLine 빈 메모 nil/한 줄 트리밍/여러 줄 첫 줄만/
  선행 빈 줄 건너뜀/CRLF).
- `Scripts/build-app.sh --install`로 release 번들(1.2.0/4) 조립·설치 성공(Info.plist
  실측 1.2.0/4 확인) → 기존 프로세스 종료 후 `~/Applications/AnhamDie.app` 재실행,
  10초 상주 스모크 그린. 유휴 CPU 0.0%(top 2초 간격 3샘플) — v1.1.1 에너지 회귀 없음
  (신규 코드는 환경값·설정 게이트뿐, 새 타이머/관찰/IO 없음). codesign seal 경고는
  §8 1차 SPM 산출물의 알려진 구조적 제약 그대로(변화 없음).

#### 미해결 (v8)

- **릴리즈 잔여**: `git push` + v1.2.0 태그 + GitHub release 발행,
  `splguyjr/homebrew-tap`의 `Casks/anhamdie.rb` version 갱신(소스 빌드 cask —
  sha256 사용 시 함께), `brew upgrade anhamdie` 실측 — 원격 푸시·별도 저장소
  작업이라 릴리즈 절차에서 수행.
- GUI 육안 확인(미리보기 표시·토글 즉시 반영·메모 있는 행 드래그 체감·브리핑 렌더)은
  헤드리스 검증 한계 — 실기 확인 권장.

---

## 18. v9 요구사항 (2026-08-04 확정 — ⌥⌘M 메인 창 토글)

- **⌥⌘M을 열기 전용 → 스마트 토글로**: ① 메인 창이 없거나 숨김 → 열고 활성화(기존 동작)
  ② 열려 있으나 키 윈도우 아님(다른 앱 뒤) → 앞으로 가져와 활성화 ③ **열려 있고 키 윈도우 → 닫기**.
  브리핑(⌥⌘T)·오버레이(⌥⌘O) 토글과 일관된 멘탈 모델.
- 닫기는 창 close(상태 저장 경로 유지 — MainWindowState 프레임·뷰 저장이 닫기 전에 반영되는지 확인).
  LSUIElement(메뉴바 상주) 상태에서 마지막 창을 닫아도 앱은 종료되지 않아야 함(현행 유지).
- Dock 클릭·applicationShouldHandleReopen·메뉴바 "메인 창 열기"는 기존 열기 동작 유지(토글 아님).
- README 단축키 표 갱신: ⌥⌘M "메인 창 열기/닫기 토글".

#### 검증 후속 수정 (2026-08-04 — OS 자동 종료 차단)

- **증상**: 마지막 창을 닫으면 macOS 자동 종료(TAL)가 약 14초 뒤 Quit AppleEvent로 앱을
  종료시킨다(unified log: `Handling Quit AppleEvent` → `applicationShouldTerminate:` 승인 →
  `terminate:`, 2회 실측). `applicationShouldTerminateAfterLastWindowClosed=false`는 '마지막 창
  닫힘' 경로만 막고 자동 종료(유휴 → Quit AppleEvent)는 못 막는다. OS가 2~6초 내 재실행하고
  `applicationWillTerminate`가 flush/save를 돌려 데이터 손실은 없으나, 재실행 공백 동안 전역
  단축키가 무반응이고 v9가 창 닫기를 1차 동선으로 만들어 노출 빈도가 커졌다.
- **수정**: SwiftUI 씬이 켠 자동 종료를 `didFinishLaunching`에서
  `ProcessInfo.processInfo.disableAutomaticTermination("메뉴바 상주")`로 끈다
  (`ResidentTermination.keepResident`, 테스트 시임 경유). Quit AppleEvent 출처(사용자 ⌘Q vs
  OS TAL)는 `applicationShouldTerminate`에서 구분 불가하므로 자동 종료 자체를 끄는 쪽이 안전.
  카운터는 balancing enable 호출 없이 앱 수명 동안 유지된다. 유휴 웨이크업 0/s 불변(새 타이머·폴링 없음).

### v9 구현 현황 (2026-08-04, 마무리 게이트 기준)

#### 완료 — §18 전부 + 릴리즈 저장소 내 반영

- **⌥⌘M 스마트 토글** (커밋 5e79ba9): `MainWindowOpener.toggle()` + 순수 판정 함수
  `toggleAction(windowExists:isVisible:isKeyWindow:appActive:)` — 없음/숨김 → `.open`,
  보이지만 키 아님(또는 앱 비활성) → `.focus`, 보이고 키+앱 활성 → `.close` 3분기.
  AppKit 상태를 입력으로 받는 nonisolated 순수 함수라 유닛 테스트 대상.
  `HotkeyService`의 `.openMain` 핸들러만 `toggle()`로 교체 — Dock 클릭
  reopen(`applicationShouldHandleReopen`)·메뉴바 「메인 창 열기」·오버레이 헤더는
  `openMain()` 유지(토글 아님). 닫기는 `window.close()`로 `willCloseNotification`을
  발화해 MainWindowConfigurator의 프레임·뷰 저장(§11.7 경로)이 닫기 전에 반영된다
  (windowShouldClose를 막는 델리게이트 없음 — 코드 주석에 제약 명시).
- **Dock 최소화 복원 보정** (커밋 af3c9a6): miniaturized 창은 `isVisible=false` →
  `.open` 분기인데 makeKeyAndOrderFront/orderFrontRegardless는 deminiaturize하지
  않아 ⌥⌘M이 무동작이었다. 전면화 공통 헬퍼 `front(_:)`가 최소화 상태면
  deminiaturize를 선행(핫키 경로 전용 — Dock 클릭 reopen은 AppKit 기본 처리가 복원).
- **OS 자동 종료(TAL) 차단** (커밋 cba43d8, 위 「검증 후속 수정」):
  `ResidentTermination.keepResident()`가 didFinishLaunching에서
  `disableAutomaticTermination`으로 SwiftUI 씬이 켠 자동 종료를 끈다(ProcessInfo
  시임 경유 유닛 테스트). `applicationShouldTerminateAfterLastWindowClosed=false`도
  명시. 유휴 웨이크업 0/s 불변(새 타이머·폴링 없음).
- **README·표시 이름**: 단축키 표 ⌥⌘M 「메인 창 열기/닫기 토글」, 설정 화면
  단축키 표시 이름(HotkeyService.displayName) 동기.
- **퀵애드 테마 배경(가독성)** (커밋 d301434·1f30d8b): 패널 배경 `.ultraThinMaterial`
  (테마 무시·흐릿) → `AppTheme.surface` 고불투명(0.98) + 다크 팔레트 그림자 보정 —
  전 프리셋 표면 위 textPrimary AAA(7.0+)·textSecondary AA(4.5+) 대비 테스트로
  잠금(테스트 212개). 1.2.1 태그 전 반영이라 버전 변경 없음.
- **릴리즈(저장소 내)**: 앱 버전 1.2.0 → **1.2.1**(CFBundleVersion/
  CURRENT_PROJECT_VERSION 5) — `Scripts/build-app.sh`·`project.yml` 동기.

#### 게이트 검증

- `swift test` 그린 — **테스트 211개**(v1.2.0 204 + v9 신규 7:
  `MainWindowToggleTests` 5 — 창 없음/숨김 → open, 보이지만 키 아님·키지만 앱
  비활성 → focus, 키+활성 → close · `ResidentTerminationTests` 2 — 사유와 함께
  정확히 1회 disable, 사유 비어 있지 않음).
- `Scripts/build-app.sh --install`로 release 번들(1.2.1/5) 조립·설치 성공(설치본
  Info.plist 실측 1.2.1/5 확인) → 기존 프로세스 종료 후
  `~/Applications/AnhamDie.app` 재실행, **25초 상주 스모크 그린**(TAL 실측 창구인
  ~14초 경과 후에도 프로세스 유지). 유휴 CPU 0.0%(top 2초 간격 3샘플) — 에너지
  회귀 없음. codesign seal 경고는 §8 1차 SPM 산출물의 알려진 구조적 제약 그대로.

#### 미해결 (v9)

- **릴리즈 잔여**: `git push` + v1.2.1 태그 + GitHub release 발행,
  `splguyjr/homebrew-tap`의 `Casks/anhamdie.rb` version 갱신, `brew upgrade
  anhamdie` 실측 — 원격 푸시·별도 저장소 작업이라 릴리즈 절차에서 수행.
- GUI 육안 확인(⌥⌘M 3분기 실기 토글 체감 — 특히 다른 앱 뒤에 있을 때 focus,
  키 윈도우일 때 close·프레임 복원, Dock 최소화 복원)은 헤드리스 검증 한계 —
  실기 확인 권장. 마지막 창 close 후 14초+ 상주(TAL 차단)는 unified log로 2회
  실측 완료(위 「검증 후속 수정」).
