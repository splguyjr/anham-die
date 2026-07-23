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

### v4 구현 현황 (2026-07-23, 3R 게이트 기준)

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

#### 미해결 (v1~v3에서 이어짐 — v4 신규 미해결 없음)

- 위젯 빌드(2차): Xcode에 Apple ID(무료 개인 팀) 추가 후
  `bash Scripts/build-with-xcode.sh --install` — 이후 App Group 마이그레이션 실측
- 1차 SPM 산출물 codesign seal 제약(로그인 자동 실행 영향)은 2차 산출물로 해소
- borderless+nonactivating 패널 가장자리 리사이즈, 패널 폭 드래그·사이드바 접힘 등
  GUI 인터랙션은 헤드리스 검증 불가 — 실기 GUI 확인 권장
