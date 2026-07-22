# AnhamDie

macOS 네이티브 투두 앱. 메뉴바에 상주하면서 **화면 맨 앞 플로팅 오버레이**와
**트리거 기반 브리핑 + Jira식 이월**로 하루를 관리한다. 알림(푸시)은 없다.
로컬 전용, 동기화 없음. macOS 15+. UI는 한국어.

## 기능

- **메인 창** — Scribble 스타일 미니멀 리스트. 최상단 행이 곧 입력창(엔터로 추가),
  체크박스·우선순위/태그 색 점·D-day 배지·이월 배지(↺n).
  행 펼침으로 메모/서브태스크/마감일/태그/우선순위 편집.
  뷰 전환: 오늘 / 예정 / 백로그 / 완료(날짜별 히스토리).
  D-day 색: 지남=빨강, 오늘=주황, 임박(≤3일)=노랑, 여유=회색.
- **메뉴바 상주** — 아이콘 클릭으로 오늘 목록 요약 + 브리핑/오버레이/메인 창 열기.
  Dock 아이콘은 설정에서 토글.
- **플로팅 오버레이** — 오늘 할 일만 담은 작은 카드. 모든 Spaces·전체화면 앱 위에 표시,
  드래그로 이동(위치 기억), 진행률 헤더, 체크박스로 바로 완료.
- **브리핑 패널** — 오늘 할 일 + 어제(이전 논리적 하루) 미완료 목록.
  항목별/일괄로 「오늘로 가져오기(이월, ↺n 증가) / 백로그로 보류 / 버리기(취소 상태로 히스토리 보관)」 선택.
- **빠른 추가** — 어디서든 Spotlight식 입력창. Enter로 오늘에 추가, Esc로 닫기.
- **완료 히스토리** — 완료는 삭제가 아니라 `completedAt` 기록. 완료 항목은 당일 리스트
  하단에 취소선으로 남고 다음 논리적 하루부터 숨김(히스토리에서 조회).
- **데스크톱 위젯** *(2차 빌드에서 활성화)* — small/medium/large, 인터랙티브 체크
  (AppIntents), App Group으로 앱과 데이터 공유. 빌드 절차는 아래 「위젯 빌드」 참고.

## 글로벌 단축키 (설정에서 변경 가능)

| 단축키 | 동작 |
|---|---|
| ⌥⌘T | 브리핑 패널 표시/숨김 (항상 즉시) |
| ⌥⌘O | 플로팅 오버레이 표시/숨김 |
| ⌥⌘N | 빠른 추가 입력창 |

## 논리적 하루와 이월

이 앱의 하루는 자정이 아니라 **기준 시각(기본 09:00, 설정 가능)**에 시작한다.
새벽 2시에 작업 중이라면 아직 "어제"다.

앱 시작 / 잠자기 해제 / 기준 시각 도달 — 세 트리거에서 논리적 오늘이
마지막 브리핑 날짜보다 앞서 있으면 브리핑 패널이 하루 한 번 자동으로 뜬다.
패널에는 어제 미완료 작업이 함께 나오고, 각 항목을:

- **오늘로 가져오기** — `scheduledDate`를 오늘로, 이월 횟수 +1 (↺n 배지)
- **백로그로 보류** — 날짜 없는 백로그로 이동
- **버리기** — 삭제가 아니라 '취소됨' 상태로 히스토리에 보관 (복구 가능)

⌥⌘T로 부른 브리핑은 판단 없이 항상 표시된다.

## 설정 항목

- **일반**: 로그인 시 자동 실행 / Dock 아이콘 표시 / 하루 기준 시각(기본 09:00)
- **단축키**: 브리핑 · 오버레이 · 빠른 추가 각각 재지정
- **오버레이**: 배경 불투명도(0.3–1.0) / 클릭 동작(즉시 완료 체크 · 메인 창 열기 · 무시) /
  최대 표시 개수(기본 7, 초과분 "+N개")
- **태그**: 이름·색상 관리

## 로그인 시 자동 실행

설정 > 일반 > 「로그인 시 자동 실행」을 켜면 된다 (`SMAppService` 사용).
켠 뒤 시스템 설정 > 일반 > 로그인 항목에 AnhamDie가 보이는지 확인.

주의: 현재 1차 SPM 빌드 산출물은 KeyboardShortcuts 리소스 번들이 .app 루트에
있어야 하는 구조적 제약으로 codesign seal 검증에 실패한다. 이 상태에선 로그인
시점 코드 검증 때문에 자동 실행이 조용히 안 될 수 있다. 자동 실행이 필요하면
아래 Xcode 빌드(`Scripts/build-with-xcode.sh --install`) 산출물을 쓰는 것을 권장.

## 데이터 저장 위치

- 1차(SPM) 빌드: `~/Library/Application Support/AnhamDie/store.json` (Codable JSON)
- 2차(Xcode, App Group 서명) 빌드: App Group 컨테이너
  (`group.<TEAMID>.com.splguyjr.anhamdie`)로 자동 마이그레이션 — 위젯과 공유
- 설정: `UserDefaults` (`com.splguyjr.anhamdie`)

## 빌드

### 1차 — SPM만으로 (Xcode 불필요, 위젯 제외)

```bash
cd /Users/woonkyung/dev/personal/anham-die
bash Scripts/build-app.sh --install   # → ~/Applications/AnhamDie.app
open ~/Applications/AnhamDie.app
```

`swift build -c release` → .app 번들 조립(LSUIElement, min macOS 15) →
ad-hoc 서명 → 설치. 외부 의존성은 KeyboardShortcuts 하나.

테스트: `swift test`

### 2차 — 위젯 빌드 (내일 할 일)

위젯/App Group은 정식 Xcode와 코드서명(무료 개인 팀으로 충분)이 필요하다. 순서대로:

1. Xcode 설치 확인: `ls /Applications/Xcode.app` (App Store 설치 완료 여부)
2. `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
3. `sudo xcodebuild -license accept`
4. Xcode를 한 번 실행 → Settings > Accounts 에 Apple ID 추가 (무료 개인 팀).
   이후 `security find-identity -v -p codesigning`에 "Apple Development" 인증서가
   보여야 한다 (없으면 아무 타깃이나 자동 서명 한 번 돌리면 생성됨).
5. `bash Scripts/build-with-xcode.sh --install`
   (XcodeGen으로 앱+위젯 프로젝트 생성 → xcodebuild → 설치. `xcodegen`이 없으면
   `brew install xcodegen`)

빌드 후 반드시 확인할 것 (App Group 식별자 검증 — 미해결 이슈):

```bash
plutil -p ~/Applications/AnhamDie.app/Contents/Info.plist | grep AnhamDieAppGroupIdentifier
codesign -d --entitlements - ~/Applications/AnhamDie.app
```

두 값이 **완전히 일치**해야 한다 (양쪽 모두 `TEAMID.` 접두사 포함).
Info.plist 쪽에서 `$(TeamIdentifierPrefix)`가 빈 문자열로 확장되면 위젯·공유
저장소가 크래시 없이 조용히 무동작한다. 상세는 PLAN.md 구현 현황 참고.
