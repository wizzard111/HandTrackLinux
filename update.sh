#!/bin/bash
# HandTrack updater for Linux: installs the newest version from GitHub; your settings are kept.
#  1. asks GitHub for the latest release and compares it with the installed version;
#  2. backs up the settings, calibration and gestures (~/.config/handtrack);
#  3. downloads the release, checks its SHA-256 and installs it with the release's own install.sh
#     (it mirrors the new program into ~/.local/lib/handtrack and deletes files it no longer has);
#  4. makes sure every setting is still there (restores from the backup otherwise),
#     deletes the download and starts the app again if it was running.
# The password is asked only if system libraries are missing or the "HandTrack Camera" set up earlier needs repair.
# Not x86_64: the release's source code is built on this computer (install.sh does it).
# Options: --check            only report whether an update exists (exit code 2 = update available)
#          --force            reinstall even when the installed version is the latest
#          --yes              no questions
#          --package FILE     install a release archive that is already downloaded
#          --no-launch        do not start the app afterwards
cd "$(dirname "$(readlink -f "$0")")" || exit 1
PAUSE=""
# Opened by double-click from a file manager: reopen in a terminal so every step is visible.
if [ ! -t 1 ] && [ -z "${UPDATER_IN_TERMINAL:-}" ]; then
    export UPDATER_IN_TERMINAL=1
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
[ -n "${UPDATER_IN_TERMINAL:-}" ] && PAUSE=1

# ---------------------------------------------------------------- what differs between the apps
APP_NAME="HandTrack"
REPO="wizzard111/HandTrackLinux"
ASSET="handtrack-linux-x86_64.tar.gz"; [ "$(uname -m)" = x86_64 ] || ASSET=""
LIB_DIR="$HOME/.local/lib/handtrack"
SETTINGS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/handtrack"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/handtrack-updater"
BACKUP_ROOT="$STATE_DIR/backups"
KEEP_BACKUPS=3
SKIP_IN_BACKUP=("*.log" "*.lock" "logs")   # logs are not settings
AFTER_NOTE=""

is_installed() { [ -x "$LIB_DIR/handtrack" ]; }
installed_version() { is_installed && "$LIB_DIR/handtrack" --version 2>/dev/null; }
is_running() { pgrep -f "$LIB_DIR/(handtrack|runtime/)" >/dev/null 2>&1; }
start_app() { (setsid "$LIB_DIR/handtrack" >/dev/null 2>&1 &); }
install_package() {   # release archive or source code archive -> its install.sh
    mkdir -p "$WORK/release" || return 1
    tar -xzf "$1" -C "$WORK/release" || { echo "cannot unpack $1"; return 1; }
    local inst; inst="$(find "$WORK/release" -mindepth 1 -maxdepth 2 -name install.sh -type f | head -n 1)"
    [ -n "$inst" ] || { echo "this is not a $APP_NAME release (install.sh is missing)"; return 1; }
    # The virtual camera is set up again only when it was set up before (it needs the password).
    local cam=""; [ -f /etc/modprobe.d/handtrack-vcam.conf ] || cam="--no-camera"
    # HANDTRACK_IN_TERMINAL: it must not open a terminal of its own; no input: it must not wait for Enter.
    HANDTRACK_IN_TERMINAL=1 bash "$inst" --yes --no-launch $cam </dev/null
}

# ---------------------------------------------------------------- common part (same in every app)
CHECK=""; FORCE=""; YES=""; LAUNCH=1; PACKAGE=""; SETUP=""; SIGN=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK=1 ;;
        --force) FORCE=1 ;;
        --yes|-y) YES=1 ;;
        --no-launch) LAUNCH="" ;;
        --package) PACKAGE="${2:-}"; shift ;;
        --pause) PAUSE=1 ;;                     # started from a menu entry: keep the window open
        --setup) SETUP=1 ;;                     # (macOS, used by the installer) signing identity + launcher
        --sign) SIGN="${2:-}"; shift ;;          # (macOS, used by the installer) sign a freshly built app
        -h|--help) sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (see --help)"; exit 1 ;;
    esac
    shift
done

BOLD=$'\033[1m'; RED=$'\033[31m'; GRN=$'\033[32m'; RST=$'\033[0m'
step() { printf "\n${BOLD}==> %s${RST}\n" "$*"; }
info() { printf "    %s\n" "$*"; }
pause() { [ -n "$PAUSE" ] && read -r -p "Press Enter to close this window." _; return 0; }
fail() {
    printf "\n${RED}Update failed: %s${RST}\n" "$*"
    [ -n "$BACKUP" ] && echo "Your settings are backed up in $BACKUP"
    pause; exit 1
}
ask() {   # yes by default; no answer possible (no terminal) = no
    [ -n "$YES" ] && return 0
    local a; read -r -p "$1 [Y/n] " a || return 1
    [[ -z "$a" || "$a" =~ ^[Yy] ]]
}
ver() { printf '%s' "$1" | grep -oE '[0-9]+(\.[0-9]+)*' | head -n 1; }
ver_ge() {   # ver_ge A B: A >= B (numeric, part by part)
    awk -v a="$1" -v b="$2" 'BEGIN { n = split(a, x, "."); m = split(b, y, "."); k = n > m ? n : m
        for (i = 1; i <= k; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 } exit 0 }'
}
fetch() {   # fetch URL FILE  (FILE "-" = print it)
    if command -v curl >/dev/null 2>&1; then
        if [ "$2" = - ]; then curl -fsSL --retry 3 --retry-delay 2 --max-time 60 -A "$APP_NAME-updater" "$1"
        else curl -fL --retry 3 --retry-delay 2 --progress-bar -A "$APP_NAME-updater" -o "$2" "$1"; fi
    elif command -v wget >/dev/null 2>&1; then
        wget -q -U "$APP_NAME-updater" -O "$2" "$1"
    else
        fail "neither curl nor wget is installed"
    fi
}
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
setting_files() {   # relative paths of the files that count as settings (logs and locks left out)
    [ -d "$SETTINGS_DIR" ] || return 0
    local args=(-name "${SKIP_IN_BACKUP[0]}") p
    for p in "${SKIP_IN_BACKUP[@]:1}"; do args+=(-o -name "$p"); done
    (cd "$SETTINGS_DIR" && find . \( "${args[@]}" \) -prune -o -type f -print | sed 's|^\./||')
}
copy_files() {   # copy_files FROM TO < list of relative paths
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        mkdir -p "$2/$(dirname "$f")" && cp -p "$1/$f" "$2/$f" || return 1
    done
}
# shellcheck disable=SC2329  # run by the EXIT trap
cleanup() {
    type cleanup_app >/dev/null 2>&1 && cleanup_app
    [ -n "$WORK" ] && rm -rf "$WORK"
    [ -n "$LOCKED" ] && rm -rf "$STATE_DIR/update.lock"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Called by an installer: only set up the signing identity and the launcher / sign its build, then stop.
if [ -n "$SETUP$SIGN" ]; then
    type sign_app >/dev/null 2>&1 || { echo "--setup and --sign are for macOS"; exit 1; }
    if [ -n "$SETUP" ]; then setup_signing; install_launcher "$SELF"; fi
    if [ -n "$SIGN" ]; then sign_app "$SIGN"; fi
    exit 0
fi

echo "================================================"
echo "  $APP_NAME updater"
echo "================================================"
mkdir -p "$STATE_DIR" || fail "cannot create $STATE_DIR"

# One updater at a time (a lock left by a crashed run is taken over).
if ! mkdir "$STATE_DIR/update.lock" 2>/dev/null; then
    pid="$(cat "$STATE_DIR/update.lock/pid" 2>/dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then fail "another update of $APP_NAME is already running"; fi
    rm -rf "$STATE_DIR/update.lock"; mkdir "$STATE_DIR/update.lock" || fail "cannot lock $STATE_DIR"
fi
LOCKED=1; echo $$ > "$STATE_DIR/update.lock/pid"

# ---------------------------------------------------------------- 1. versions
INSTALLED=""
if is_installed; then
    INSTALLED="$(ver "$(installed_version)")"
    # The version this updater installed last; the newer one counts (an app may report an old number).
    saved="$(ver "$(cat "$STATE_DIR/installed-version" 2>/dev/null)")"
    if [ -n "$saved" ] && { [ -z "$INSTALLED" ] || ! ver_ge "$INSTALLED" "$saved"; }; then INSTALLED="$saved"; fi
    info "Installed: ${INSTALLED:+v}${INSTALLED:-unknown version}"
else
    info "Installed: not installed"
fi

LATEST=""; URL=""; DIGEST=""
if [ -n "$PACKAGE" ]; then
    [ -f "$PACKAGE" ] || fail "file not found: $PACKAGE"
    PACKAGE="$(cd "$(dirname "$PACKAGE")" && pwd)/$(basename "$PACKAGE")"
    info "Package:   $PACKAGE"
    [ -n "$CHECK" ] && fail "--check needs the internet (it cannot be used with --package)"
else
    json="$(fetch "https://api.github.com/repos/$REPO/releases/latest" - 2>/dev/null)" || json=""
    TAG="$(printf '%s' "$json" | tr -d '\n' | grep -oE '"tag_name": *"[^"]*"' | head -n 1 | sed -E 's/.*"([^"]*)"$/\1/')"
    if [ -z "$TAG" ]; then
        # The GitHub API answers 60 questions an hour per address; the release page names the latest version too.
        json=""
        TAG="$(curl -fsSIL --max-time 30 -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null |
               sed -n 's|.*/releases/tag/||p')"
        [ -n "$TAG" ] || fail "could not ask GitHub for the latest version. Check the internet connection."
    fi
    LATEST="$(ver "$TAG")"
    if [ -n "$ASSET" ] && [ -z "$json" ]; then
        URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"; DIGEST="-"
        info "Latest:    v$LATEST"
    elif [ -n "$ASSET" ]; then
        # The release's assets: name ... size ... digest ... browser_download_url (one field per line here).
        # shellcheck disable=SC2020  # tr: each of , { } starts a new line
        read -r URL DIGEST SIZE <<< "$(printf '%s' "$json" | tr ',{}' '\n\n\n' | awk -v want="$ASSET" '
            /"name": *"/ { n = $0; sub(/.*"name": *"/, "", n); sub(/".*/, "", n); cur = n; d = "-"; s = 0 }
            cur != want { next }
            /"size": *[0-9]/ { s = $0; gsub(/[^0-9]/, "", s) }
            /"digest": *"sha256:/ { d = $0; sub(/.*sha256:/, "", d); sub(/".*/, "", d) }
            /"browser_download_url": *"/ { u = $0; sub(/.*"browser_download_url": *"/, "", u); sub(/".*/, "", u)
                                          print u, d, s; exit }')"
        DIGEST="${DIGEST:--}"; SIZE="${SIZE:-0}"
        [ -n "$URL" ] || fail "release $TAG has no $ASSET"
        info "Latest:    v$LATEST ($(awk -v s="$SIZE" 'BEGIN { printf "%.1f", s / 1048576 }') MB)"
    else
        # No ready-made program for this computer: the release's source code is built here.
        URL="https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz"; DIGEST="-"
        info "Latest:    v$LATEST (source code, built on this computer)"
    fi
    UP_TO_DATE=""
    [ -n "$INSTALLED" ] && ver_ge "$INSTALLED" "$LATEST" && UP_TO_DATE=1
    if [ -n "$CHECK" ]; then
        if [ -n "$UP_TO_DATE" ]; then echo "$APP_NAME is up to date."; exit 0; fi
        echo "An update is available: v$LATEST"; exit 2
    fi
    if [ -n "$UP_TO_DATE" ] && [ -z "$FORCE" ]; then
        printf "\n${GRN}%s is up to date.${RST} (--force reinstalls it.)\n" "$APP_NAME"; pause; exit 0
    fi
fi
ask "Install ${LATEST:+v}${LATEST:-the package} now? Your settings are kept." || { echo "Nothing changed."; pause; exit 0; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/$(printf '%s' "$APP_NAME" | tr -cd 'A-Za-z0-9')-update.XXXXXX")" || fail "cannot create a temporary folder"

# ---------------------------------------------------------------- 2. download (before closing the app)
if [ -z "$PACKAGE" ]; then
    step "Downloading ${ASSET:-the source code}"
    PACKAGE="$WORK/${ASSET:-source.tar.gz}"
    fetch "$URL" "$PACKAGE" || fail "download failed. Check the internet connection and try again."
    if [ "$DIGEST" != - ]; then
        [ "$(sha256 "$PACKAGE")" = "$DIGEST" ] || fail "the download is damaged (SHA-256 does not match). Try again."
        info "SHA-256 checked"
    fi
fi

# ---------------------------------------------------------------- 3. settings backup
BACKUP=""
FILES="$(setting_files)"
COUNT=0; [ -n "$FILES" ] && COUNT="$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')"
if [ "$COUNT" -gt 0 ]; then
    step "Backing up the settings"
    BACKUP="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)${INSTALLED:+-v$INSTALLED}"
    printf '%s\n' "$FILES" | copy_files "$SETTINGS_DIR" "$BACKUP" || fail "could not back up the settings to $BACKUP"
    info "$COUNT files -> $BACKUP"
    # Only the newest backups are kept.
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +$((KEEP_BACKUPS + 1)) |
        while IFS= read -r old; do rm -rf "${old:?}"; done
else
    info "No settings yet: nothing to back up."
fi

# ---------------------------------------------------------------- 4. install
WAS_RUNNING=""; is_running && WAS_RUNNING=1
step "Installing $APP_NAME${LATEST:+ v$LATEST}"
[ -n "$WAS_RUNNING" ] && info "$APP_NAME is running: it is closed for the update and started again afterwards."
install_package "$PACKAGE" || fail "the installation did not succeed (see the messages above)"
NOW="$(ver "$(installed_version)")"; NOW="${NOW:-$LATEST}"
if [ -n "$NOW" ]; then echo "$NOW" > "$STATE_DIR/installed-version"; else rm -f "$STATE_DIR/installed-version"; fi
type after_install >/dev/null 2>&1 && after_install   # (macOS) the launcher gets the new updater

# ---------------------------------------------------------------- 5. settings check
if [ "$COUNT" -gt 0 ]; then
    step "Checking the settings"
    MISSING="$(printf '%s\n' "$FILES" | while IFS= read -r f; do [ -e "$SETTINGS_DIR/$f" ] || printf '%s\n' "$f"; done)"
    if [ -n "$MISSING" ]; then
        printf '%s\n' "$MISSING" | copy_files "$BACKUP" "$SETTINGS_DIR" || fail "could not restore the settings from $BACKUP"
        info "Restored from the backup: $(printf '%s' "$MISSING" | tr '\n' ' ')"
    else
        info "All $COUNT files are in place."
    fi
fi

if [ -n "$WAS_RUNNING" ] && [ -n "$LAUNCH" ] && ! is_running; then step "Starting $APP_NAME"; start_app; fi
printf "\n${GRN}%s is updated%s. Settings kept.${RST}\n" "$APP_NAME" "${NOW:+ to v$NOW}"
[ -n "$AFTER_NOTE" ] && printf '%s\n' "$AFTER_NOTE"
pause
exit 0
