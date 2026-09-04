#!/bin/bash
# 构建 StealthReader.app（伪装名可在此处统一修改）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="StealthReader"     # .app 文件名与可执行文件名
BUNDLE_NAME="StealthReader"  # Dock / 菜单栏 / 窗口显示的应用名
ARCHS="arm64 x86_64"         # 通用二进制：Apple 芯片与 Intel 都能运行

rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS" "$APP_NAME.app/Contents/Resources"

ARCH_FLAGS=""
for a in $ARCHS; do ARCH_FLAGS="$ARCH_FLAGS -arch $a"; done

# swiftc 不支持一次传多个 -arch：按 target 分别编译再 lipo 合并
rm -rf .build-bin && mkdir -p .build-bin
OBJ="$APP_NAME.app/Contents/MacOS/$APP_NAME"
LIPO_INPUTS=""
for a in $ARCHS; do
    swiftc -O -target "${a}-apple-macosx11.0" -o ".build-bin/$a" main.swift
    LIPO_INPUTS="$LIPO_INPUTS .build-bin/$a"
done
lipo -create -output "$OBJ" $LIPO_INPUTS

sed -e "s/ConsoleLog/$APP_NAME/g" \
    -e "s/<string>Console<\/string>/<string>$BUNDLE_NAME<\/string>/g" \
    Info.plist > "$APP_NAME.app/Contents/Info.plist"
cp ConsoleIcon.icns "$APP_NAME.app/Contents/Resources/ConsoleIcon.icns"
touch "$APP_NAME.app"

codesign --force -s - --timestamp=none "$APP_NAME.app" 2>/dev/null \
    || codesign --force -s - "$APP_NAME.app"

echo "Built $PWD/$APP_NAME.app"
lipo -info "$APP_NAME.app/Contents/MacOS/$APP_NAME" || true
