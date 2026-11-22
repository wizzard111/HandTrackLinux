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
have() { printf "   present: %s\n" "$*"; }
did() { printf "   + %s\n" "$*"; }
pause() { [ -n "${HANDTRACK_IN_TERMINAL:-}" ] && read -r -p "Press Enter to close" _; return 0; }
fail() { printf "\n${RED}INSTALL FAILED: %s${RST}\nLog: %s\n" "$*" "$LOG"; pause; exit 1; }
ask() { [ -n "$YES" ] && return 0; local a; read -r -p "$1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy] ]]; }

LIB="$HOME/.local/lib/handtrack"
BIN="$HOME/.local/bin"
SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"
ICON="$SHARE/icons/hicolor/256x256/apps/handtrack.png"
DESKTOP="$SHARE/applications/handtrack.desktop"
DESKTOP_UN="$SHARE/applications/handtrack-uninstall.desktop"

printf "${PUR}==================================================${RST}\n"
printf "   H A N D T R A C K   —   installer\n"
printf "   %s, %s\n" "$( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}" )" "$(uname -m)"
printf "${PUR}==================================================${RST}\n"

if [ -x app/handtrack/handtrack ]; then MODE=release; PKG=app
elif [ -f src/handtrack/__init__.py ]; then MODE=source; PKG=packaging/linux
else fail "neither app/ nor src/ found next to this script"; fi

# Running the installer again only fills in what is missing or changed: the
# system libraries, the camera, Python, libraries, models and unchanged program
# files are left alone.

# ---------------------------------------------------------------- 1. system part (sudo once)
SUDO=sudo; [ "$(id -u)" -eq 0 ] && SUDO=""
libs_ready() {
    local l
    for l in libxcb-cursor.so.0 libxkbcommon-x11.so.0 libEGL.so.1 libGL.so.1 libglib-2.0.so.0; do
        ldconfig -p 2>/dev/null | grep -q "$l" || return 1
    done
}
camera_ready() {
    [ -f /etc/modprobe.d/handtrack-vcam.conf ] && grep -qx "HandTrack Camera" /sys/class/video4linux/video42/name 2>/dev/null
}
step "Checking what is already installed"
if [ -d "$LIB" ]; then have "$LIB"; else did "fresh install: $LIB"; fi
if libs_ready && { [ -z "$CAMERA" ] || camera_ready; }; then
    have "system libraries"
    [ -n "$CAMERA" ] && have "'HandTrack Camera' (/dev/video42)"
elif [ -z "$CAMERA" ]; then
    step "System libraries (password needed)"
    $SUDO bash "$PKG/vcam-setup.sh" --libs-only || echo "(failed, continuing)"
else
    step "System libraries and the virtual camera \"HandTrack Camera\" (password needed)"
    echo "The password is not shown while typing; that is normal."
    if $SUDO bash "$PKG/vcam-setup.sh"; then
        echo "OK"
    else
        echo "${RED}Camera not set up; the app still works and can set it up later from Settings.${RST}"
    fi
fi

# ---------------------------------------------------------------- 2. the program
step "Closing a running copy"
pkill -f "$LIB/(handtrack|runtime/)" 2>/dev/null && sleep 1
mkdir -p "$LIB" "$BIN" "$(dirname "$ICON")" "$(dirname "$DESKTOP")"
# Mirror SRC into DST: copy only new or changed files, delete files that are no
# longer part of the program. Extra arguments are exclusions: "/name" matches a
# top-level entry, "name" any path component. Excluded paths are neither copied
# nor deleted. Uses rsync when present, otherwise compares files with cmp.
_excluded() {   # _excluded REL PATTERN...
    local rel="$1" p; shift
    for p in "$@"; do
        case "$p" in
            /*) [ "${rel%%/*}" = "${p#/}" ] && return 0 ;;
            *)  case "/$rel/" in */"$p"/*) return 0 ;; esac ;;
        esac
    done
    return 1
}
sync_tree() {
    local src="$1" dst="$2"; shift 2
    local ex=() p n=0 f d rel
    mkdir -p "$dst"
    if command -v rsync >/dev/null 2>&1; then
        for p in "$@"; do ex+=(--exclude="$p"); done
        local out
        out="$(rsync -a --delete --itemize-changes "${ex[@]}" "$src/" "$dst/")" || return 1
        # Attribute-only lines start with "."; the rest are copies and deletions.
        n=$(printf '%s\n' "$out" | grep -c '^[^.]')
    else
        while IFS= read -r -d '' f; do
            rel="${f#"$src"/}"; d="$dst/$rel"
            _excluded "$rel" "$@" && continue
            if [ -L "$f" ]; then
                [ -L "$d" ] && [ "$(readlink "$f")" = "$(readlink "$d")" ] && continue
            elif [ -f "$d" ] && [ ! -L "$d" ] && cmp -s "$f" "$d"; then
                continue
            fi
            mkdir -p "$(dirname "$d")" && rm -rf "$d" && cp -a "$f" "$d" || return 1
            n=$((n + 1))
        done < <(find "$src" \( -type f -o -type l \) -print0)
        while IFS= read -r -d '' d; do
            rel="${d#"$dst"/}"
            _excluded "$rel" "$@" && continue
            [ -e "$src/$rel" ] || [ -L "$src/$rel" ] || { rm -f "$d"; n=$((n + 1)); }
        done < <(find "$dst" \( -type f -o -type l \) -print0)
        find "$dst" -mindepth 1 -type d -empty -delete 2>/dev/null
    fi
    if [ "$n" = 0 ]; then have "$(basename "$dst") — up to date"
    else did "$(basename "$dst") — files updated: $n"; fi
}
# Copy a file only when its content differs.
put() { cmp -s "$1" "$2" || cp -f "$1" "$2"; }

if [ "$MODE" = release ]; then
    step "The program"
    # Mirrors the whole folder; a source-code install (app, runtime...) is replaced.
    sync_tree app/handtrack "$LIB" /uninstall.sh /driver /self-test.log || fail "copy"
    mkdir -p "$LIB/driver" && put app/vcam-setup.sh "$LIB/driver/vcam-setup.sh" 2>/dev/null
    put app/icon.png "$ICON" 2>/dev/null
else
    case "$(uname -m)" in
        x86_64|amd64) UVARCH=x86_64-unknown-linux-gnu ;;
        aarch64|arm64) UVARCH=aarch64-unknown-linux-gnu ;;
        *) fail "unsupported architecture: $(uname -m)" ;;
    esac
    # A release install leaves its bundled program behind.
    rm -rf "$LIB/_internal"
    # runtime/ (the private Python) holds absolute paths, so it is built in place
    # and reused on upgrades.
    step "Python 3.12 and libraries"
    UV="$LIB/runtime/uv"
    if [ -x "$UV" ]; then have uv; else
        mkdir -p "$LIB/runtime"
        curl -fsSL "https://github.com/astral-sh/uv/releases/latest/download/uv-$UVARCH.tar.gz" \
            | tar -xz -C "$LIB/runtime" --strip-components=1 || fail "could not download uv"
        rm -f "$LIB/runtime/uvx"
        did uv
    fi
    export UV_PYTHON_INSTALL_DIR="$LIB/runtime/python"
    PY="$LIB/runtime/venv/bin/python"
    if "$PY" -c "import sys; sys.exit(0 if sys.version_info[:2] == (3, 12) else 1)" 2>/dev/null; then
        have "Python 3.12"
    else
        # A broken environment from an earlier attempt is rebuilt instead of reused.
        echo "   Installing Python 3.12 (first time ~1 minute)"
        "$UV" venv --clear --python 3.12 "$LIB/runtime/venv" || fail "uv venv"
        did "Python 3.12"
    fi
    # Offline first: succeeds without the network when every library is already
    # installed (or cached); only otherwise download what is missing.
    # Older installs carry the GUI OpenCV builds, matplotlib and sounddevice. All
    # OpenCV builds share one cv2 folder, so remove them together with the
    # headless one; it is reinstalled cleanly just below.
    EXTRAS="$("$UV" pip list --python "$PY" --format freeze 2>/dev/null \
        | grep -ioE '^(opencv-python|opencv-contrib-python|matplotlib|sounddevice)==' | tr -d '=' | tr '\n' ' ')"
    if [ -n "$EXTRAS" ]; then
        "$UV" pip uninstall --python "$PY" $EXTRAS opencv-python-headless >/dev/null 2>&1
        did "removed unneeded packages: $EXTRAS"
    fi
    # overrides.txt drops mediapipe's unneeded extras (GUI OpenCV, matplotlib, audio).
    if "$UV" pip install --offline --quiet --python "$PY" -r packaging/requirements.txt \
            --override packaging/overrides.txt >/dev/null 2>&1; then
        have "libraries"
    else
        echo "   Downloading libraries (first time ~2-5 minutes)"
        "$UV" pip install --python "$PY" -r packaging/requirements.txt --override packaging/overrides.txt \
            || fail "pip install"
        did "libraries"
    fi

    step "The program"
    sync_tree src "$LIB/app" __pycache__ || fail "copy"
    mkdir -p "$LIB/driver"
    put packaging/linux/vcam-setup.sh "$LIB/driver/vcam-setup.sh"
    LAUNCH_SH="$(mktemp)"
    printf '%s\n' '#!/bin/sh' 'HERE="$(dirname "$(readlink -f "$0")")"' \
        'cd "$HERE/app" && exec "$HERE/runtime/venv/bin/python" -m handtrack "$@"' > "$LAUNCH_SH"
    put "$LAUNCH_SH" "$LIB/handtrack"; rm -f "$LAUNCH_SH"
    put src/handtrack/assets/icon.png "$ICON"

    step "Models"
    # Downloads only missing files.
    PYTHONPATH="$LIB/app" "$PY" packaging/fetch_deps.py "$LIB" || fail "fetch_deps"
fi
LAUNCHER="$LIB/handtrack"
chmod +x "$LAUNCHER"
put uninstall.sh "$LIB/uninstall.sh" && chmod +x "$LIB/uninstall.sh"

step "Self-test"
if ! QT_QPA_PLATFORM=offscreen "$LAUNCHER" --self-test > "$LIB/self-test.log" 2>&1; then
    tail -15 "$LIB/self-test.log"
    fail "self-test"
fi
did "$(tail -1 "$LIB/self-test.log")"

# ---------------------------------------------------------------- 3. menu entry, commands
step "Application menu"
ln -sf "$LAUNCHER" "$BIN/handtrack"
ln -sf "$LIB/uninstall.sh" "$BIN/handtrack-uninstall"
# Menu entries are rewritten only when they are missing or differ.
MENU_CHANGED=""
put_entry() {
    if cmp -s "$1" "$2"; then have "$(basename "$2")"
    else cp -f "$1" "$2" && chmod +x "$2"; did "$(basename "$2")"; MENU_CHANGED=1; fi
    rm -f "$1"
}
cat > "$DESKTOP.new" <<EOF
[Desktop Entry]
Type=Application
Name=HandTrack
GenericName=Gesture camera
Comment=Gestures, gaze tracking, face hiding and a virtual camera for calls
Exec=$LAUNCHER
Icon=$ICON
Terminal=false
Categories=AudioVideo;Video;Utility;
Keywords=camera;webcam;gesture;discord;telegram;zoom;
StartupWMClass=handtrack
EOF
put_entry "$DESKTOP.new" "$DESKTOP"
cat > "$DESKTOP_UN.new" <<EOF
[Desktop Entry]
Type=Application
Name=Uninstall HandTrack
Exec=$LIB/uninstall.sh
Icon=$ICON
Terminal=true
Categories=Utility;
NoDisplay=false
EOF
put_entry "$DESKTOP_UN.new" "$DESKTOP_UN"
if [ -n "$MENU_CHANGED" ]; then
    command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$DESKTOP")" 2>/dev/null
fi
# Refresh the icon cache every time: a redesigned icon keeps the same file name.
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q "$SHARE/icons/hicolor" 2>/dev/null
case ":$PATH:" in *":$BIN:"*) ;; *) echo "(The handtrack command works after you log in again.)";; esac

if [ -n "$LAUNCH" ]; then
    step "Starting HandTrack"
    (setsid "$LAUNCHER" >/dev/null 2>&1 &)
fi
printf "\n${GRN}DONE. HandTrack is in your application menu. Camera for calls: \"HandTrack Camera\".${RST}\n"
echo "Uninstall:  handtrack-uninstall   (or ./uninstall.sh)"
pause
