#!/usr/bin/env bash
# 将 dist/Nopeject.app 打包为 dist/Nopeject.pkg
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Nopeject.app"
PKG="dist/Nopeject.pkg"

if [ ! -d "$APP" ]; then
    echo "错误：未找到 $APP，请先运行 scripts/make-app.sh" >&2
    exit 1
fi

echo "==> 打包 $PKG"
rm -f "$PKG"
productbuild --component "$APP" /Applications "$PKG"

echo "==> 完成：$PKG"
