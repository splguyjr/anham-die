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
