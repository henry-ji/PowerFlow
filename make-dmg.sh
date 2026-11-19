#!/bin/zsh
# 打包可分发 DMG：dist/PowerFlow.dmg（含 Applications 拖拽安装快捷方式）
# 签名：优先 Developer ID Application，其次 Apple Development，均无则 ad-hoc。
# 注意：无 Developer ID + 公证时，其他 Mac 首次打开需绕过 Gatekeeper（见 README）。
set -e
cd "$(dirname "$0")"
./make-app.sh
APP=dist/PowerFlow.app

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')
fi
if [[ -n "$IDENTITY" ]]; then
  echo "签名身份: $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  echo "无签名身份，使用 ad-hoc 签名"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

STAGE=dist/dmg-stage
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Power Flow" -srcfolder "$STAGE" -ov -format UDZO dist/PowerFlow.dmg
rm -rf "$STAGE"

MNT=$(mktemp -d)
hdiutil attach dist/PowerFlow.dmg -nobrowse -readonly -mountpoint "$MNT" >/dev/null
ls "$MNT"
codesign --verify --strict "$MNT/PowerFlow.app" && echo "DMG 内签名校验通过"
hdiutil detach "$MNT" >/dev/null
rmdir "$MNT"
echo "已生成 dist/PowerFlow.dmg"
