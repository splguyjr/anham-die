#!/bin/bash
# swift build -c release → dist/AnhamDie.app 조립 → ad-hoc 서명 (→ --install 시 ~/Applications 복사)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCRATCH="${SCRATCH_PATH:-.build}"
APP_NAME="AnhamDie"
BUNDLE_ID="com.splguyjr.anhamdie"
APP="$ROOT/dist/$APP_NAME.app"

# 가드: CLT 툴체인은 SwiftData 매크로(@Model)를 컴파일하지 못한다 (PLAN §8).
# 재도입은 xcode-select를 정식 Xcode로 전환한 뒤에만 — 그 전엔 빌드를 즉시 실패시킨다.
if grep -rnE '^[[:space:]]*@Model([[:space:]]|$)|^[[:space:]]*import SwiftData' "$ROOT/Sources" "$ROOT/Widget" 2>/dev/null; then
    echo "!! @Model / import SwiftData 발견 — CLT 툴체인(SwiftDataMacros 플러그인 부재)에서 빌드 불가."
    echo "   SwiftData 도입은 정식 Xcode 전환 후에만 가능합니다. (pitfall-checklist: swiftdata-spm)"
    exit 1
fi

echo "==> swift build -c release"
swift build -c release --scratch-path "$SCRATCH"
BIN_DIR="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"

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
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

echo "==> ad-hoc 서명"
codesign --force -s - "$APP"
codesign --verify --strict "$APP"

# KeyboardShortcuts SPM 리소스 번들 — 누락 시 설정 화면의 Recorder가 Bundle.module
# fatalError로 설치본을 즉사시킨다. SPM이 생성한 resource_bundle_accessor는
# Bundle.main.bundleURL(=.app 루트) 바로 아래에서 번들을 찾으므로 Resources/가 아니라 루트에 둔다.
# 루트 추가분은 앱 seal 밖이라 서명 검증 후에 복사한다 — strict 재검증은 'unsealed contents'로
# 실패하지만 로컬 ad-hoc + 비격리 실행에는 영향 없음(실측: 정상 구동).
echo "==> KeyboardShortcuts 리소스 번들 복사 (.app 루트)"
cp -R "$KS_BUNDLE" "$APP/"
codesign --force -s - "$APP/KeyboardShortcuts_KeyboardShortcuts.bundle"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$APP_NAME.app"
    cp -R "$APP" "$HOME/Applications/$APP_NAME.app"
    echo "==> 설치 완료: $HOME/Applications/$APP_NAME.app"
fi

echo "==> 완료: $APP"
