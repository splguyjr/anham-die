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

# ── 1. DEVELOPMENT_TEAM 감지 → local.xcconfig ────────────────────────────────
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

# 파일이 없거나 DEVELOPMENT_TEAM이 비어 있으면 감지해서 채운다.
# (xcodegen은 configFiles로 지정된 local.xcconfig가 없으면 spec 검증 에러 — 항상 생성해 둔다.)
needs_team() {
    [[ ! -f "$XCCONFIG" ]] && return 0
    ! grep -Eq '^DEVELOPMENT_TEAM *= *[A-Z0-9]{4,}' "$XCCONFIG"
}

if needs_team; then
    echo "==> local.xcconfig 없음/팀 미설정 — 생성 시도"
    if TEAM_ID="$(detect_team_id)"; then
        echo "==> 코드서명 팀 감지: $TEAM_ID"
        cat > "$XCCONFIG" <<CFG
// 자동 생성됨 (gitignore). App Group·위젯 서명에 쓰는 개인/개발 팀 ID.
DEVELOPMENT_TEAM = $TEAM_ID
CFG
    else
        echo "!! 코드서명 인증서를 찾지 못했습니다."
        echo "   Xcode에 Apple ID(무료 개인 팀)로 로그인한 뒤, 아래처럼 팀 ID를 채우세요:"
        echo "     echo 'DEVELOPMENT_TEAM = XXXXXXXXXX' > \"$XCCONFIG\""
        echo "   (Team ID는 https://developer.apple.com/account → Membership 또는"
        echo "    Xcode > Settings > Accounts 에서 확인)"
        cat > "$XCCONFIG" <<'CFG'
// 자동 생성됨 (gitignore). 아래에 10자리 Team ID를 채우세요.
DEVELOPMENT_TEAM =
CFG
    fi
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

# ── 5. 설치 ──────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$APP_NAME.app"
    cp -R "$BUILT_APP" "$HOME/Applications/$APP_NAME.app"
    echo "==> 설치 완료: $HOME/Applications/$APP_NAME.app"
fi
