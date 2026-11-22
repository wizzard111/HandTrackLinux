#!/bin/bash
# HandTrack uninstaller for Linux: removes the program, the menu entries and the
# commands; asks about the settings and the "HandTrack Camera" configuration.
# Options: --yes (remove everything without asking), --keep-settings
YES=""; KEEP=""
for a in "$@"; do case "$a" in --yes|-y) YES=1 ;; --keep-settings) KEEP=1 ;; esac; done

if [ ! -t 1 ] && [ -z "${HANDTRACK_IN_TERMINAL:-}" ]; then
    export HANDTRACK_IN_TERMINAL=1
    me="$(readlink -f "$0")"
    for t in x-terminal-emulator gnome-terminal konsole kgx ptyxis kitty alacritty xfce4-terminal mate-terminal foot xterm; do
        command -v "$t" >/dev/null 2>&1 || continue
        case "$t" in
            gnome-terminal|kgx|ptyxis) exec "$t" -- bash "$me" "$@" ;;
            kitty|foot)                exec "$t" bash "$me" "$@" ;;
            xfce4-terminal)            exec "$t" -x bash "$me" "$@" ;;
            *)                         exec "$t" -e bash "$me" "$@" ;;
        esac
    done
fi

RED=$'\033[1;31m'; GRN=$'\033[1;32m'; PUR=$'\033[35m'; RST=$'\033[0m'
ask() { [ -n "$YES" ] && return 0; local a; read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[YyДд] ]]; }
LIB="$HOME/.local/lib/handtrack"
BIN="$HOME/.local/bin"
SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/handtrack"

printf "${PUR}==================================================${RST}\n"
printf "   H A N D T R A C K   —   удаление / uninstall\n"
printf "${PUR}==================================================${RST}\n"

REMOVE_CFG=""; REMOVE_CAM=""
if [ -z "$KEEP" ] && ask "Удалить настройки и калибровку? / Delete settings and calibration? ($CFG)"; then REMOVE_CFG=1; fi
if [ -f /etc/modprobe.d/handtrack-vcam.conf ] && ask "Убрать виртуальную камеру «HandTrack Camera»? / Remove the virtual camera?"; then
    REMOVE_CAM=1
fi

printf "${RED}>> Удаляю программу / Removing the program${RST}\n"
# Only the program's processes (this script may itself live in $LIB; bash keeps
# reading a deleted script from its open file, so removing the folder is safe).
pkill -f "$LIB/(handtrack|runtime/)" 2>/dev/null
rm -rf "$LIB"
rm -f "$BIN/handtrack" "$BIN/handtrack-uninstall" \
      "$SHARE/applications/handtrack.desktop" "$SHARE/applications/handtrack-uninstall.desktop" \
      "$SHARE/icons/hicolor/256x256/apps/handtrack.png"
command -v update-desktop-database >/dev/null && update-desktop-database "$SHARE/applications" 2>/dev/null

if [ -n "$REMOVE_CFG" ]; then rm -rf "$CFG" && echo "Настройки удалены / settings deleted."
elif [ -d "$CFG" ]; then echo "Настройки сохранены / settings kept: $CFG"; fi

if [ -n "$REMOVE_CAM" ]; then
    printf "${RED}>> Убираю камеру (нужен пароль) / Removing the camera (password needed)${RST}\n"
    sudo sh -c 'rm -f /etc/modprobe.d/handtrack-vcam.conf /etc/modules-load.d/handtrack-vcam.conf; modprobe -r v4l2loopback 2>/dev/null; true'
fi
printf "\n${GRN}HandTrack удалён. / HandTrack has been removed.${RST}\n"
[ -n "${HANDTRACK_IN_TERMINAL:-}" ] && read -r -p "Enter — закрыть / close" _
exit 0
