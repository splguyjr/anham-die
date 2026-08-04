#!/bin/bash
# swift build -c release → dist/AnhamDie.app 조립 → ad-hoc 서명 (→ --install 시 ~/Applications 복사)
#
# 알려진 구조적 제약 (1차 SPM 산출물):
#   swift-build가 KeyboardShortcuts 타깃에 생성하는 resource_bundle_accessor.swift는
#   Bundle.main.bundleURL(=.app 루트) 직하와 빌드 스크래치 절대경로 두 곳만 탐색한다
#   (Contents/Resources는 탐색하지 않음 — 생성 소스에서 확인).
#   따라서 리소스 번들을 .app 루트(Contents 밖)에 둘 수밖에 없고, codesign은 번들 루트의
#   Contents 외 항목을 unsealed content로 취급하므로 최종 산출물은 codesign --verify를
#   (strict/비-strict 모두) 구조적으로 통과할 수 없다.
#   → 로컬 비격리 실행은 정상. 단 SMAppService(BTM) 로그인 항목은 로그인 시 코드 검증
#     실패로 조용히 실행되지 않을 수 있다. 검증 가능한 seal이 필요하면 2차 경로
#     Scripts/build-with-xcode.sh(리소스가 Contents/Resources에 정상 seal됨)를 사용한다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCRATCH="${SCRATCH_PATH:-.build}"
APP_NAME="AnhamDie"
BUNDLE_ID="com.splguyjr.anhamdie"
APP="$ROOT/dist/$APP_NAME.app"
XCODE_SCRIPT="Scripts/build-with-xcode.sh"

has_full_xcode() {
    [[ -d /Applications/Xcode.app/Contents/Developer ]] && return 0
    [[ "$(xcode-select -p 2>/dev/null)" == *".app/Contents/Developer"* ]] && return 0
    return 1
}

# 가드: CLT 툴체인은 SwiftData 매크로(@Model)를 컴파일하지 못한다 (PLAN §8).
# 재도입은 xcode-select를 정식 Xcode로 전환한 뒤에만 — 그 전엔 빌드를 즉시 실패시킨다.
if grep -rnE '^[[:space:]]*@Model([[:space:]]|$)|^[[:space:]]*import SwiftData' "$ROOT/Sources" "$ROOT/Widget" 2>/dev/null; then
    echo "!! @Model / import SwiftData 발견 — CLT 툴체인(SwiftDataMacros 플러그인 부재)에서 빌드 불가."
    echo "   SwiftData 도입은 정식 Xcode 전환 후에만 가능합니다. (pitfall-checklist: swiftdata-spm)"
    exit 1
fi

# Homebrew 등 이미 샌드박스인 환경에서는 SPM의 자체 sandbox-exec가 중첩 금지로 실패한다
# (sandbox_apply: Operation not permitted) → 그런 환경만 ANHAM_DISABLE_SPM_SANDBOX=1로 해제.
SANDBOX_FLAG=""
[[ "${ANHAM_DISABLE_SPM_SANDBOX:-0}" == "1" ]] && SANDBOX_FLAG="--disable-sandbox"

echo "==> swift build -c release"
swift build -c release --scratch-path "$SCRATCH" $SANDBOX_FLAG
BIN_DIR="$(swift build -c release --scratch-path "$SCRATCH" $SANDBOX_FLAG --show-bin-path)"

echo "==> $APP 조립"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AnhamDieApp" "$APP/Contents/MacOS/$APP_NAME"

KS_BUNDLE="$BIN_DIR/KeyboardShortcuts_KeyboardShortcuts.bundle"
if [[ ! -d "$KS_BUNDLE" ]]; then
    echo "!! KeyboardShortcuts 리소스 번들을 찾지 못했습니다: $KS_BUNDLE"
    exit 1
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ko</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.1</string>
    <key>CFBundleVersion</key>
    <string>5</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# 리소스 번들 복사 '전'에 서명·검증한다. 이 시점의 실패는 진짜 서명 문제이므로 중단.
echo "==> ad-hoc 서명 + seal 사전 검증 (루트 복사 전 — 이 검증은 반드시 통과해야 함)"
codesign --force -s - "$APP"
codesign --verify --strict "$APP"

# KeyboardShortcuts SPM 리소스 번들 — 누락 시 설정 화면의 Recorder가 Bundle.module
# fatalError로 설치본을 즉사시킨다. 파일 상단 주석의 제약대로 .app 루트에만 둘 수 있다.
echo "==> KeyboardShortcuts 리소스 번들 복사 (.app 루트 — 이 시점부터 앱 seal 밖 콘텐츠 발생)"
cp -R "$KS_BUNDLE" "$APP/"
codesign --force -s - "$APP/KeyboardShortcuts_KeyboardShortcuts.bundle"

# 최종 산출물의 검증 상태를 실측해 그대로 보고한다 (숨기지 않는다).
if codesign --verify --strict "$APP" 2>/dev/null; then
    SEAL_BROKEN=0
    echo "==> codesign --verify --strict 통과 — 산출물 seal 유효"
    echo "    (예상 밖: 툴체인의 리소스 탐색/서명 규칙이 바뀌었을 수 있음. 아래 경고는 해당 없음)"
else
    SEAL_BROKEN=1
    echo ""
    echo "!! 경고: 최종 산출물은 codesign --verify에 실패하는 상태입니다 (알려진 제약)."
    echo "   - 원인: KeyboardShortcuts 리소스 번들이 .app 루트(Contents 밖)에 있어"
    echo "     'unsealed contents present in the bundle root'로 seal이 깨짐."
    echo "   - 영향: 로컬 비격리 실행은 정상. 단 SMAppService 로그인 항목 등록 시"
    echo "     로그인 시점 코드 검증 실패로 자동 실행이 조용히 깨질 수 있음."
    if has_full_xcode; then
        echo "   - 권장: 정식 Xcode가 감지되었습니다 — seal이 유효한 산출물은"
        echo "     $XCODE_SCRIPT [--install] 로 빌드하세요 (리소스가 Contents/Resources에 정상 seal됨)."
    else
        echo "   - 해소: 정식 Xcode 설치 후 $XCODE_SCRIPT [--install] 로 빌드하면 해소됩니다."
    fi
    echo ""
fi

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$APP_NAME.app"
    cp -R "$APP" "$HOME/Applications/$APP_NAME.app"
    echo "==> 설치 완료: $HOME/Applications/$APP_NAME.app"
    if [[ "$SEAL_BROKEN" == "1" ]]; then
        echo ""
        echo "!! 설치본 주의: 이 설치본은 서명 검증 실패 상태이며, '로그인 시 자동 실행'"
        echo "   등록(SMAppService/BTM)이 실패하거나 로그인 시 조용히 실행되지 않을 수 있습니다."
        echo "   확인 절차:"
        echo "   1) 앱 설정에서 '로그인 시 자동 실행'을 켠 직후 SMAppService.status가"
        echo "      .enabled인지 확인 (시스템 설정 > 일반 > 로그인 항목에 $APP_NAME 표시 여부)"
        echo "   2) 재로그인 후 앱이 실제로 자동 실행되는지 1회 실측 (진단: sudo sfltool dumpbtm)"
        echo "   3) 자동 실행이 안 되면 $XCODE_SCRIPT --install 산출물로 교체"
        echo ""
    fi
fi

echo "==> 완료: $APP"
if [[ "$SEAL_BROKEN" == "1" ]]; then
    echo "    (codesign --verify 실패 상태 — 위 경고 참조)"
fi
