#!/bin/zsh
# 打包为 dist/PowerFlow.app（LSUIElement 菜单栏应用，含图标）
set -e
cd "$(dirname "$0")"
swift build -c release
APP=dist/PowerFlow.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PowerFlowApp "$APP/Contents/MacOS/PowerFlow"
cp scripts/pm-helper.sh "$APP/Contents/Resources/pm-helper.sh"

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
swift scripts/make-icon.swift "$ICONSET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
  sips -z $((size * 2)) $((size * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  sips -z $size $size "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Power Flow</string>
  <key>CFBundleDisplayName</key><string>Power Flow</string>
  <key>CFBundleIdentifier</key><string>local.powerflow.app</string>
  <key>CFBundleExecutable</key><string>PowerFlow</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
echo "已生成 $APP —— 双击运行，或拷贝到 /Applications。"
