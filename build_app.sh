#!/bin/bash
# Сборка KeyClean.app. Нужны только Command Line Tools.
#   ./build_app.sh            собрать → build/KeyClean.app
#   ./build_app.sh --install  поставить в /Applications и запустить
#   ./build_app.sh --dmg      образ для установки → build/KeyClean.dmg
set -euo pipefail
cd "$(dirname "$0")"

# Universal: Apple Silicon и Intel. Если так собрать не вышло, собираем под этот Mac.
ARCHS=(--arch arm64 --arch x86_64)
if ! swift build -c release "${ARCHS[@]}"; then
  echo "→ Universal не собрался, собираю под текущий Mac"
  ARCHS=()
  swift build -c release
fi
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/KeyClean"

# Значок рисуем один раз: он лежит в Resources и не меняется от сборки к сборке.
if [[ ! -f Resources/AppIcon.icns ]]; then
  ICONS="$(mktemp -d)"
  "$BIN" --render "$ICONS"
  mkdir "$ICONS/AppIcon.iconset"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$ICONS/icon.png" --out "$ICONS/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size*2)) $((size*2)) "$ICONS/icon.png" --out "$ICONS/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONS/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$ICONS"
fi

# Собираем во временной папке: iCloud навешивает на файлы в ~/Documents атрибуты, которые ломают codesign.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/KeyClean.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KeyClean"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"

# Постоянный сертификат: macOS не сбрасывает разрешение после пересборки.
# Свой можно задать так: SIGN_IDENTITY="Мой сертификат" ./build_app.sh. Если его нет, подпись ad-hoc.
SIGN_IDENTITY="${SIGN_IDENTITY:-KeySwitch Dev}"
IDENTITY="-"
if security find-identity -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY"; then
  IDENTITY="$SIGN_IDENTITY"
fi
codesign --force --deep --sign "$IDENTITY" "$APP"
echo "→ Подписано: $IDENTITY"

mkdir -p build
rm -rf build/KeyClean.app
ditto "$APP" build/KeyClean.app

if [[ "${1:-}" == "--dmg" ]]; then
  DMGSRC="$STAGE/dmg"
  mkdir -p "$DMGSRC"
  ditto "$APP" "$DMGSRC/KeyClean.app"
  ln -s /Applications "$DMGSRC/Applications"
  rm -f build/KeyClean.dmg
  hdiutil create -volname "KeyClean" -srcfolder "$DMGSRC" -ov -format UDZO "$STAGE/KeyClean.dmg" >/dev/null
  codesign --force --sign "$IDENTITY" "$STAGE/KeyClean.dmg"
  cp "$STAGE/KeyClean.dmg" build/KeyClean.dmg
  echo "→ Образ: build/KeyClean.dmg"
elif [[ "${1:-}" == "--install" ]]; then
  pkill -x KeyClean 2>/dev/null || true
  rm -rf /Applications/KeyClean.app
  ditto "$APP" /Applications/KeyClean.app
  open /Applications/KeyClean.app
  echo "→ Установлено в /Applications и запущено"
else
  echo "Готово: build/KeyClean.app"
fi
