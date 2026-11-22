#!/bin/bash
# HandTrack installer for Linux (x86_64 / aarch64).
#
# Release download: copies the ready-made program from app/.
# Source download:  fetches uv, which installs a private Python 3.12 and the
#                   libraries into the program folder (nothing system-wide).
# Installs for the current user: ~/.local/lib/handtrack, the "handtrack" command,
# an application-menu entry and "handtrack-uninstall".
# Asks for the password once: Qt libraries + the "HandTrack Camera" (v4l2loopback).
# Options: --yes (no questions), --no-launch, --no-camera
cd "$(dirname "$(readlink -f "$0")")" || exit 1
YES=""; LAUNCH=1; CAMERA=1
for a in "$@"; do case "$a" in
    --yes|-y) YES=1 ;; --no-launch) LAUNCH="" ;; --no-camera) CAMERA="" ;;
esac; done

# Double-clicked in a file manager: reopen in a terminal so every step is visible.
if [ ! -t 1 ] && [ -z "${HANDTRACK_IN_TERMINAL:-}" ] && [ -z "${HANDTRACK_LOGGING:-}" ]; then
    export HANDTRACK_IN_TERMINAL=1
    me="$(readlink -f "$0")"
    for t in x-terminal-emulator gnome-terminal konsole kgx ptyxis kitty alacritty xfce4-terminal mate-terminal foot wezterm xterm; do
        command -v "$t" >/dev/null 2>&1 || continue
        case "$t" in
            gnome-terminal|kgx|ptyxis) exec "$t" -- bash "$me" "$@" ;;
            kitty|foot)                exec "$t" bash "$me" "$@" ;;
            xfce4-terminal)            exec "$t" -x bash "$me" "$@" ;;
            wezterm)                   exec "$t" start -- bash "$me" "$@" ;;
            *)                         exec "$t" -e bash "$me" "$@" ;;
        esac
    done
fi

LOG="${TMPDIR:-/tmp}/handtrack-install.log"
# Run once more with all output copied to the log; keep the real exit status
# (an "exec > >(tee)" redirect would turn every failure into exit code 0).
if [ -z "${HANDTRACK_LOGGING:-}" ]; then
    export HANDTRACK_LOGGING=1
    bash "$(readlink -f "$0")" "$@" 2>&1 | tee "$LOG"
    exit "${PIPESTATUS[0]}"
fi

RED=$'\033[1;31m'; GRN=$'\033[1;32m'; PUR=$'\033[35m'; RST=$'\033[0m'
step() { printf "\n${RED}>> %s${RST}\n" "$*"; }
pause() { [ -n "${HANDTRACK_IN_TERMINAL:-}" ] && read -r -p "Enter — закрыть / close" _; return 0; }
fail() { printf "\n${RED}ОШИБКА УСТАНОВКИ / INSTALL FAILED: %s${RST}\nЖурнал / log: %s\n" "$*" "$LOG"; pause; exit 1; }
ask() { [ -n "$YES" ] && return 0; local a; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[YyДд] ]]; }

LIB="$HOME/.local/lib/handtrack"
BIN="$HOME/.local/bin"
SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"
ICON="$SHARE/icons/hicolor/256x256/apps/handtrack.png"
DESKTOP="$SHARE/applications/handtrack.desktop"
DESKTOP_UN="$SHARE/applications/handtrack-uninstall.desktop"

printf "${PUR}==================================================${RST}\n"
printf "   H A N D T R A C K   —   установка / installer\n"
printf "   %s, %s\n" "$( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}" )" "$(uname -m)"
printf "${PUR}==================================================${RST}\n"

if [ -x app/handtrack/handtrack ]; then MODE=release; PKG=app
elif [ -f src/handtrack/__init__.py ]; then MODE=source; PKG=packaging/linux
else fail "рядом нет ни app/, ни src/ / neither app/ nor src/ found next to this script"; fi

# ---------------------------------------------------------------- 1. system part (sudo once)
SUDO=sudo; [ "$(id -u)" -eq 0 ] && SUDO=""
if [ -z "$CAMERA" ]; then
    step "Системные библиотеки (нужен пароль) / system libraries (password needed)"
    $SUDO bash "$PKG/vcam-setup.sh" --libs-only || echo "(не удалось — продолжаю / failed, continuing)"
else
    step "Системные библиотеки и виртуальная камера «HandTrack Camera» (нужен пароль) / system libraries and the virtual camera (password needed)"
    echo "Пароль при вводе не отображается — это нормально. / The password is not shown while typing."
    if $SUDO bash "$PKG/vcam-setup.sh"; then
        echo "OK"
    else
        echo "${RED}Камера не настроена — программа работает, камеру можно включить позже из её настроек.${RST}"
        echo "Camera not set up; the app still works and can set it up later from Settings."
    fi
fi

# ---------------------------------------------------------------- 2. the program
step "Закрываю старую версию / Closing a running copy"
pkill -f "$LIB/(handtrack|runtime/)" 2>/dev/null && sleep 1
mkdir -p "$LIB" "$BIN" "$(dirname "$ICON")" "$(dirname "$DESKTOP")"
# Replace the previous version but keep runtime/ (the private Python): its
# files hold absolute paths, so it is built in place and reused on upgrades.
find "$LIB" -mindepth 1 -maxdepth 1 ! -name runtime -exec rm -rf {} +

if [ "$MODE" = release ]; then
    step "Копирую программу / Copying the program"
    rm -rf "$LIB/runtime"
    cp -a app/handtrack/. "$LIB/" || fail "copy"
    mkdir -p "$LIB/driver" && cp -f app/vcam-setup.sh "$LIB/driver/" 2>/dev/null
    cp -f app/icon.png "$ICON" 2>/dev/null
else
    case "$(uname -m)" in
        x86_64|amd64) UVARCH=x86_64-unknown-linux-gnu ;;
        aarch64|arm64) UVARCH=aarch64-unknown-linux-gnu ;;
        *) fail "архитектура $(uname -m) не поддерживается / unsupported architecture" ;;
    esac
    step "Скачиваю uv (установщик Python) / Getting uv"
    UVTMP="$(mktemp -d)"
    curl -fsSL "https://github.com/astral-sh/uv/releases/latest/download/uv-$UVARCH.tar.gz" \
        | tar -xz -C "$UVTMP" --strip-components=1 || fail "не удалось скачать uv / could not download uv"
    export UV_PYTHON_INSTALL_DIR="$LIB/runtime/python"
    # A broken environment from an earlier attempt is rebuilt instead of reused.
    "$LIB/runtime/venv/bin/python" -c "" 2>/dev/null || rm -rf "$LIB/runtime/venv"
    step "Ставлю Python 3.12 и библиотеки (первый раз ~2-5 минут) / Installing Python 3.12 and libraries"
    "$UVTMP/uv" venv --allow-existing --python 3.12 "$LIB/runtime/venv" || fail "uv venv"
    "$UVTMP/uv" pip install --python "$LIB/runtime/venv/bin/python" -r packaging/requirements.txt         || fail "pip install"
    step "Копирую программу и скачиваю модели / Copying the program, downloading models"
    cp -a src "$LIB/app"
    mkdir -p "$LIB/driver"
    cp -f packaging/linux/vcam-setup.sh "$LIB/driver/"
    PYTHONPATH="$LIB/app" "$LIB/runtime/venv/bin/python" packaging/fetch_deps.py "$LIB" || fail "fetch_deps"
    cat > "$LIB/handtrack" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
cd "$HERE/app" && exec "$HERE/runtime/venv/bin/python" -m handtrack "$@"
EOF
    cp -f src/handtrack/assets/icon.png "$ICON"
    rm -rf "$UVTMP"
fi
LAUNCHER="$LIB/handtrack"
chmod +x "$LAUNCHER"
cp -f uninstall.sh "$LIB/uninstall.sh" && chmod +x "$LIB/uninstall.sh"

step "Проверка программы / Self-test"
if ! QT_QPA_PLATFORM=offscreen "$LAUNCHER" --self-test > "$LIB/self-test.log" 2>&1; then
    tail -15 "$LIB/self-test.log"
    fail "self-test"
fi
tail -1 "$LIB/self-test.log"

# ---------------------------------------------------------------- 3. menu entry, commands
step "Добавляю в меню приложений / Adding to the application menu"
ln -sf "$LAUNCHER" "$BIN/handtrack"
ln -sf "$LIB/uninstall.sh" "$BIN/handtrack-uninstall"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=HandTrack
GenericName=Gesture camera
Comment=Gestures, gaze tracking, face hiding and a virtual camera for calls
Comment[ru]=Жесты, взгляд, скрытие лица и виртуальная камера для звонков
Exec=$LAUNCHER
Icon=$ICON
Terminal=false
Categories=AudioVideo;Video;Utility;
Keywords=camera;webcam;gesture;discord;telegram;zoom;
StartupWMClass=handtrack
EOF
cat > "$DESKTOP_UN" <<EOF
[Desktop Entry]
Type=Application
Name=Uninstall HandTrack
Name[ru]=Удалить HandTrack
Exec=$LIB/uninstall.sh
Icon=$ICON
Terminal=true
Categories=Utility;
NoDisplay=false
EOF
chmod +x "$DESKTOP" "$DESKTOP_UN"
command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$DESKTOP")" 2>/dev/null
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q "$SHARE/icons/hicolor" 2>/dev/null
case ":$PATH:" in *":$BIN:"*) ;; *) echo "(Команда handtrack заработает после повторного входа / after re-login)";; esac

if [ -n "$LAUNCH" ]; then
    step "Запускаю HandTrack / Starting HandTrack"
    (setsid "$LAUNCHER" >/dev/null 2>&1 &)
fi
printf "\n${GRN}ГОТОВО. HandTrack в меню приложений. Камера для звонков: «HandTrack Camera».${RST}\n"
printf "${GRN}DONE. HandTrack is in your application menu. Camera for calls: \"HandTrack Camera\".${RST}\n"
echo "Удалить / uninstall:  handtrack-uninstall   (или / or ./uninstall.sh)"
pause
