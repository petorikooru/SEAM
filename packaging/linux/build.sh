#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENV="$PROJECT_ROOT/.packaging-venv"
PYTHON="$VENV/bin/python"
DIST="$PROJECT_ROOT/dist"
RELEASE="$PROJECT_ROOT/release"
GUI_BUNDLE="$DIST/KAI Bridge Inspection"
VERSION="5.2.0"
DEB_ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$DEB_ARCH" in
  amd64) APPIMAGE_ARCH="x86_64" ;;
  arm64) APPIMAGE_ARCH="aarch64" ;;
  *) APPIMAGE_ARCH="$DEB_ARCH" ;;
esac

if [[ "${1:-}" == "--clean" ]]; then
  rm -rf "$VENV" "$DIST" "$PROJECT_ROOT/build" "$RELEASE"
fi

if [[ ! -x "$PYTHON" ]]; then
  if command -v python3.12 >/dev/null 2>&1; then
    python3.12 -m venv "$VENV"
  else
    python3 -m venv "$VENV"
  fi
fi

"$PYTHON" -m pip install --upgrade pip wheel
"$PYTHON" -m pip install -e "$PROJECT_ROOT[packaging]"

cd "$PROJECT_ROOT"
"$PYTHON" -m PyInstaller --clean --noconfirm packaging/pyinstaller/gui.spec

[[ -d "$GUI_BUNDLE" ]] || { echo "GUI bundle missing: $GUI_BUNDLE" >&2; exit 1; }
chmod +x "$GUI_BUNDLE/KAI Bridge Inspection"

mkdir -p "$RELEASE"
tar -C "$DIST" -czf "$RELEASE/KAI_Bridge_Inspection_v${VERSION}_Linux_${DEB_ARCH}_Portable.tar.gz" "KAI Bridge Inspection"

DEB_ROOT="$PROJECT_ROOT/build/deb-root"
rm -rf "$DEB_ROOT"
mkdir -p \
  "$DEB_ROOT/DEBIAN" \
  "$DEB_ROOT/opt/kai-bridge-inspection" \
  "$DEB_ROOT/usr/bin" \
  "$DEB_ROOT/usr/share/applications" \
  "$DEB_ROOT/usr/share/icons/hicolor/scalable/apps"
cp -a "$GUI_BUNDLE/." "$DEB_ROOT/opt/kai-bridge-inspection/"
ln -s "/opt/kai-bridge-inspection/KAI Bridge Inspection" "$DEB_ROOT/usr/bin/kai-bridge-inspection"
cp "$PROJECT_ROOT/packaging/linux/kai-bridge-inspection.desktop" "$DEB_ROOT/usr/share/applications/"
cp "$PROJECT_ROOT/src/kai_bridge_inspection/qml/assets/KAI.svg" "$DEB_ROOT/usr/share/icons/hicolor/scalable/apps/kai-bridge-inspection.svg"
cat > "$DEB_ROOT/DEBIAN/control" <<CONTROL
Package: kai-bridge-inspection
Version: $VERSION
Section: utils
Priority: optional
Architecture: $DEB_ARCH
Maintainer: Project Team
Depends: libasound2 | libasound2t64, libdbus-1-3, libegl1, libfontconfig1, libgbm1, libgl1, libnss3, libx11-6, libxcomposite1, libxdamage1, libxkbcommon-x11-0, libxrandr2, libxcb-cursor0
Description: KAI Bridge Inspection IoT Dashboard
 PySide6/QML desktop dashboard consuming normalized telemetry from Node-RED WebSocket outputs.
CONTROL

if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb --build --root-owner-group "$DEB_ROOT" "$RELEASE/kai-bridge-inspection_${VERSION}_${DEB_ARCH}.deb"
else
  echo "dpkg-deb not found; skipped .deb creation." >&2
fi

APPDIR="$PROJECT_ROOT/build/KAI_Bridge_Inspection.AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/scalable/apps"
cp -a "$GUI_BUNDLE/." "$APPDIR/usr/bin/"
cp "$PROJECT_ROOT/packaging/linux/AppRun" "$APPDIR/AppRun"
cp "$PROJECT_ROOT/packaging/linux/kai-bridge-inspection.appimage.desktop" "$APPDIR/kai-bridge-inspection.desktop"
cp "$PROJECT_ROOT/packaging/linux/kai-bridge-inspection.desktop" "$APPDIR/usr/share/applications/"
cp "$PROJECT_ROOT/src/kai_bridge_inspection/qml/assets/KAI.svg" "$APPDIR/kai-bridge-inspection.svg"
cp "$PROJECT_ROOT/src/kai_bridge_inspection/qml/assets/KAI.svg" "$APPDIR/usr/share/icons/hicolor/scalable/apps/kai-bridge-inspection.svg"
ln -s "KAI Bridge Inspection" "$APPDIR/usr/bin/kai-bridge-inspection"
chmod +x "$APPDIR/AppRun" "$APPDIR/usr/bin/KAI Bridge Inspection"

if command -v appimagetool >/dev/null 2>&1; then
  ARCH="$APPIMAGE_ARCH" appimagetool "$APPDIR" "$RELEASE/KAI_Bridge_Inspection_v${VERSION}_Linux_${APPIMAGE_ARCH}.AppImage"
else
  echo "appimagetool not found; AppDir prepared at $APPDIR but AppImage was skipped." >&2
fi

echo "Build outputs: $RELEASE"
