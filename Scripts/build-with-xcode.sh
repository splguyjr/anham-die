#!/bin/bash
# PLAN §8 2차: XcodeGen으로 앱+위젯 프로젝트 생성 → 정식 Xcode로 빌드 → ~/Applications 설치.
#   1) local.xcconfig 준비 (DEVELOPMENT_TEAM 자동 감지, 실패 시 안내)
#   2) xcodegen generate
#   3) 정식 Xcode(DEVELOPER_DIR) 감지
#   4) xcodebuild build
#   5) 설치 (--install)
# 사용: Scripts/build-with-xcode.sh [--install]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="AnhamDie"
SCHEME="AnhamDie"
PROJECT="$ROOT/$APP_NAME.xcodeproj"
XCCONFIG="$ROOT/local.xcconfig"
DERIVED="$ROOT/.build-xcode"
CONFIG="Release"

# ── 1. 팀 ID 감지 → local.xcconfig (ANHAM_TEAM_ID = 단일 소스) ──────────────
# App Group ID는 `$(ANHAM_TEAM_ID).com.splguyjr.anhamdie` 하나로 확장된다:
#   local.xcconfig: ANHAM_TEAM_ID = <10자 팀ID>, DEVELOPMENT_TEAM = $(ANHAM_TEAM_ID)
#   project.yml:    ANHAM_APP_GROUP_ID = $(DEVELOPMENT_TEAM).com.splguyjr.anhamdie
#   Info.plist(AnhamDieAppGroupIdentifier)·앱/위젯 엔타이틀먼트 모두 $(ANHAM_APP_GROUP_ID) 참조.
# $(TeamIdentifierPrefix)는 Info.plist 확장에서 빈 문자열이 될 수 있어 쓰지 않는다 (PLAN §9).
# Apple Development/Distribution 인증서의 OU(=10자 Team ID)를 추출한다.
detect_team_id() {
    local cn ou
    cn="$(security find-identity -v -p codesigning 2>/dev/null \
          | grep -Eo '"(Apple Development|Apple Distribution|Mac Developer)[^"]*"' \
          | head -1 | sed 's/^"//; s/"$//')"
    [[ -z "$cn" ]] && return 1
    ou="$(security find-certificate -c "$cn" -p 2>/dev/null \
          | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
          | sed -n 's/.*organizationalUnitName *= *//p' | head -1 | tr -d '[:space:]')"
    [[ -z "$ou" ]] && return 1
    echo "$ou"
}

# 기존 local.xcconfig에서 팀 ID를 읽는다 (ANHAM_TEAM_ID 우선, 과거 형식 DEVELOPMENT_TEAM 직접 지정도 수용).
existing_team_id() {
    [[ -f "$XCCONFIG" ]] || return 1
    local id
    id="$(sed -nE 's/^ *ANHAM_TEAM_ID *= *([A-Z0-9]{4,}).*/\1/p' "$XCCONFIG" | head -1)"
    [[ -z "$id" ]] && id="$(sed -nE 's/^ *DEVELOPMENT_TEAM *= *([A-Z0-9]{4,}).*/\1/p' "$XCCONFIG" | head -1)"
    [[ -z "$id" ]] && return 1
    echo "$id"
}

write_xcconfig() {
    cat > "$XCCONFIG" <<CFG
// 자동 생성됨 (gitignore). 팀 ID의 단일 소스 — App Group ID·서명 모두 여기서 확장된다.
// (project.yml: ANHAM_APP_GROUP_ID = \$(DEVELOPMENT_TEAM).com.splguyjr.anhamdie)
ANHAM_TEAM_ID = $1
DEVELOPMENT_TEAM = \$(ANHAM_TEAM_ID)
CFG
}

# (xcodegen은 configFiles로 지정된 local.xcconfig가 없으면 spec 검증 에러 — 항상 생성해 둔다.)
if TEAM_ID="$(existing_team_id)"; then
    # 과거 형식(DEVELOPMENT_TEAM 직접 지정)이면 ANHAM_TEAM_ID 형식으로 승격한다.
    grep -Eq '^ *ANHAM_TEAM_ID *= *[A-Z0-9]{4,}' "$XCCONFIG" || {
        echo "==> local.xcconfig를 ANHAM_TEAM_ID 형식으로 갱신"
        write_xcconfig "$TEAM_ID"
    }
    echo "==> 팀 ID (local.xcconfig): $TEAM_ID"
elif TEAM_ID="$(detect_team_id)"; then
    echo "==> 코드서명 팀 감지: $TEAM_ID"
    write_xcconfig "$TEAM_ID"
else
    TEAM_ID=""
    echo "!! 코드서명 인증서를 찾지 못했습니다."
    echo "   Xcode에 Apple ID(무료 개인 팀)로 로그인한 뒤, 아래처럼 팀 ID를 채우세요:"
    echo "     echo 'ANHAM_TEAM_ID = XXXXXXXXXX' > \"$XCCONFIG\""
    echo "     echo 'DEVELOPMENT_TEAM = \$(ANHAM_TEAM_ID)' >> \"$XCCONFIG\""
    echo "   (Team ID는 https://developer.apple.com/account → Membership 또는"
    echo "    Xcode > Settings > Accounts 에서 확인)"
    cat > "$XCCONFIG" <<'CFG'
// 자동 생성됨 (gitignore). 아래에 10자리 Team ID를 채우세요 (App Group·서명의 단일 소스).
ANHAM_TEAM_ID =
DEVELOPMENT_TEAM = $(ANHAM_TEAM_ID)
CFG
fi

# ── 2. XcodeGen ──────────────────────────────────────────────────────────────
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "!! xcodegen이 없습니다. 설치: brew install xcodegen"
    exit 1
fi
echo "==> xcodegen generate"
xcodegen generate --spec "$ROOT/project.yml"

# ── 3. 정식 Xcode 감지 ───────────────────────────────────────────────────────
find_developer_dir() {
    if [[ -n "${DEVELOPER_DIR:-}" && -d "$DEVELOPER_DIR" && "$DEVELOPER_DIR" == *Xcode* ]]; then
        echo "$DEVELOPER_DIR"; return 0
    fi
    local sel; sel="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$sel" == *"/Xcode"*".app/"* ]]; then echo "$sel"; return 0; fi
    local app
    for app in /Applications/Xcode.app /Applications/Xcode-*.app "$HOME/Applications/Xcode.app"; do
        [[ -d "$app/Contents/Developer" ]] && { echo "$app/Contents/Developer"; return 0; }
    done
    return 1
}

if ! DEV_DIR="$(find_developer_dir)"; then
    echo ""
    echo "!! 정식 Xcode를 찾지 못했습니다. (현재: $(xcode-select -p 2>/dev/null || echo 없음))"
    echo "   위젯/App Group은 CommandLineTools만으로는 빌드할 수 없습니다."
    echo "   App Store에서 Xcode 설치 후 다시 실행하세요. 프로젝트($APP_NAME.xcodeproj)는 이미 생성됨."
    exit 2
fi
export DEVELOPER_DIR="$DEV_DIR"
echo "==> DEVELOPER_DIR = $DEVELOPER_DIR"

# ── 4. 빌드 ──────────────────────────────────────────────────────────────────
echo "==> xcodebuild ($CONFIG)"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    -destination 'generic/platform=macOS' \
    build

BUILT_APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "!! 빌드 산출물을 찾지 못했습니다: $BUILT_APP"
    exit 3
fi
echo "==> 빌드 완료: $BUILT_APP"

# ── 5. App Group ID 검증 (PLAN §9 미해결 이슈의 자동 확인) ────────────────────
# Info.plist(AnhamDieAppGroupIdentifier)와 앱/위젯 엔타이틀먼트의 그룹 값이
# 전부 `<TEAMID>.com.splguyjr.anhamdie`로 완전히 일치해야 위젯·공유 저장소가 동작한다.
verify_app_group() {
    local plist_group app_ent_group widget_ent_group tmp fail=0
    plist_group="$(/usr/libexec/PlistBuddy -c 'Print :AnhamDieAppGroupIdentifier' \
                   "$BUILT_APP/Contents/Info.plist" 2>/dev/null || true)"
    tmp="$(mktemp -d)"
    codesign -d --entitlements "$tmp/app.plist" --xml "$BUILT_APP" 2>/dev/null || true
    app_ent_group="$(/usr/libexec/PlistBuddy \
                     -c 'Print :com.apple.security.application-groups:0' \
                     "$tmp/app.plist" 2>/dev/null || true)"
    local appex="$BUILT_APP/Contents/PlugIns/AnhamDieWidget.appex"
    if [[ -d "$appex" ]]; then
        codesign -d --entitlements "$tmp/widget.plist" --xml "$appex" 2>/dev/null || true
        widget_ent_group="$(/usr/libexec/PlistBuddy \
                            -c 'Print :com.apple.security.application-groups:0' \
                            "$tmp/widget.plist" 2>/dev/null || true)"
    else
        widget_ent_group="(위젯 .appex 없음)"
        fail=1
    fi
    rm -rf "$tmp"

    echo "==> App Group 검증"
    echo "    Info.plist            : ${plist_group:-(없음)}"
    echo "    앱 엔타이틀먼트        : ${app_ent_group:-(없음)}"
    echo "    위젯 엔타이틀먼트      : ${widget_ent_group:-(없음)}"

    local expected_re='^[A-Z0-9]{10}\.com\.splguyjr\.anhamdie$'
    [[ "$plist_group" =~ $expected_re ]] || fail=1
    [[ "$plist_group" == "$app_ent_group" ]] || fail=1
    [[ "$plist_group" == "$widget_ent_group" ]] || fail=1

    if [[ $fail -ne 0 ]]; then
        echo "!! App Group ID 불일치/형식 오류 — 세 값이 모두 'TEAMID.com.splguyjr.anhamdie'로"
        echo "   일치해야 합니다. local.xcconfig의 ANHAM_TEAM_ID와 project.yml의"
        echo "   ANHAM_APP_GROUP_ID(=\$(DEVELOPMENT_TEAM).com.splguyjr.anhamdie)를 확인하세요."
        return 1
    fi
    echo "==> App Group 검증 통과: $plist_group"
}
verify_app_group || exit 4

# ── 6. 설치 ──────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$APP_NAME.app"
    cp -R "$BUILT_APP" "$HOME/Applications/$APP_NAME.app"
    echo "==> 설치 완료: $HOME/Applications/$APP_NAME.app"
fi
