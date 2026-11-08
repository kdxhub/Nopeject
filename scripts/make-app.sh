#!/usr/bin/env bash
# 构建 Nopeject.app 产物到 dist/
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --disable-sandbox

APP="dist/Nopeject.app"
BIN=".build/$CONFIG"

echo "==> 打包 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Nopeject" "$APP/Contents/MacOS/Nopeject"
cp "$BIN/nopejectd" "$APP/Contents/MacOS/nopejectd"

# 前端资源（SwiftPM bundle）
if [ -d "$BIN/Nopeject_NopejectApp.bundle" ]; then
    cp -R "$BIN/Nopeject_NopejectApp.bundle" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Nopeject</string>
    <key>CFBundleDisplayName</key>
    <string>Nopeject</string>
    <key>CFBundleIdentifier</key>
    <string>com.neonai.nopeject</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Nopeject</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Neonai &amp; kdxiaoyi. MIT License.</string>

    <!-- 访达快捷操作：接收目录并定位其所在挂载点 -->
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Nopeject：定位挂载点</string>
            </dict>
            <key>NSMessage</key>
            <string>locateMountPoint</string>
            <key>NSSendTypes</key>
            <array>
                <string>NSFilenamesPboardType</string>
            </array>
            <key>NSRequiredContext</key>
            <dict>
                <key>NSApplicationIdentifier</key>
                <string>com.apple.finder</string>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> 代码签名（ad-hoc）"
codesign --force --deep --sign - "$APP"

echo "==> 完成：$APP"
