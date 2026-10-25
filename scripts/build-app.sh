#!/bin/sh
set -eu

usage() {
    printf '用法: sh scripts/build-app.sh [--adhoc-sign]\n'
}
SIGN=0
case "${1:-}" in
    '') ;;
    --adhoc-sign) SIGN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
    usage >&2
    exit 2
fi

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
if [ "$(uname -s)" != Darwin ]; then
    printf '错误：仅支持在 macOS 上构建。\n' >&2
    exit 1
fi
if [ ! -f Package.swift ]; then
    printf '错误：缺少 Package.swift。\n' >&2
    exit 1
fi

swift build -c release --product MKbd
swift build -c release --product mkbdctl
BIN=$(swift build -c release --show-bin-path)
for NAME in MKbd mkbdctl; do
    if [ ! -x "$BIN/$NAME" ]; then
        printf '错误：未找到可执行文件 %s\n' "$BIN/$NAME" >&2
        exit 1
    fi
done

mkdir -p dist
STAGE=$(mktemp -d "$ROOT/dist/.MKbd.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
trap 'exit 1' HUP INT TERM
APP="$STAGE/MKbd.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/MKbd" "$APP/Contents/MacOS/MKbd"
cp "$BIN/mkbdctl" "$APP/Contents/MacOS/mkbdctl"
chmod 755 "$APP/Contents/MacOS/MKbd" "$APP/Contents/MacOS/mkbdctl"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleExecutable</key><string>MKbd</string>
    <key>CFBundleIdentifier</key><string>local.mkbd.MKbd</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>MKbd</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
if [ "$SIGN" -eq 1 ]; then
    codesign --force --sign - "$APP/Contents/MacOS/mkbdctl"
    codesign --force --sign - "$APP"
    codesign --verify --deep --strict "$APP"
fi
# Replace the old bundle only after build, staging and optional signing succeed.
if [ -e "$ROOT/dist/MKbd.app" ]; then
    rm -rf "$ROOT/dist/MKbd.app"
fi
mv "$APP" "$ROOT/dist/MKbd.app"
printf '已生成 %s/dist/MKbd.app\n' "$ROOT"
