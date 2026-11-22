#!/bin/bash
# Builds the Linux release: dist/handtrack-linux-<arch>.tar.gz
#   root: install.sh, uninstall.sh, HOW-TO-INSTALL.txt     app/: the program
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/../.."
PY="${PYTHON:-python3}"
export PYTHONPATH="$PWD/src"
"$PY" packaging/fetch_deps.py
"$PY" -m PyInstaller --noconfirm --clean --log-level WARN --distpath dist --workpath build/pyinstaller packaging/linux/handtrack.spec
QT_QPA_PLATFORM=offscreen dist/handtrack/handtrack --self-test
ARCH="$(uname -m)"
PKG=dist/package/handtrack
rm -rf dist/package && mkdir -p "$PKG/app"
cp install.sh uninstall.sh HOW-TO-INSTALL.txt "$PKG/"
cp -a dist/handtrack "$PKG/app/handtrack"
cp packaging/linux/vcam-setup.sh src/handtrack/assets/icon.png LICENSE docs/THIRD_PARTY_NOTICES.md "$PKG/app/"
chmod +x "$PKG"/*.sh "$PKG/app/vcam-setup.sh" "$PKG/app/handtrack/handtrack"
tar -C dist/package -czf "dist/handtrack-linux-$ARCH.tar.gz" handtrack
echo "Release: dist/handtrack-linux-$ARCH.tar.gz ($(du -h "dist/handtrack-linux-$ARCH.tar.gz" | cut -f1))"
