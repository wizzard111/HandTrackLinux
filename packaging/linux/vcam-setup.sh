#!/bin/bash
# Run as root (the installer uses sudo, the app uses pkexec).
# Installs what HandTrack needs from the system:
#   * the libraries Qt, OpenCV and MediaPipe need (xcb, EGL, OpenGL/GLES, GLib);
#   * the v4l2loopback kernel module, set up as a camera named "HandTrack Camera"
#     (/dev/video42) that loads on every boot.
# --remove      undo the camera configuration (the package stays installed)
# --libs-only   only the Qt libraries, no camera
set -u
LABEL="HandTrack Camera"
NR=42
MODPROBE_CONF=/etc/modprobe.d/handtrack-vcam.conf
LOAD_CONF=/etc/modules-load.d/handtrack-vcam.conf

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo." >&2
    exit 1
fi

if [ "${1:-}" = "--remove" ]; then
    rm -f "$MODPROBE_CONF" "$LOAD_CONF"
    modprobe -r v4l2loopback 2>/dev/null || true
    echo "HandTrack camera configuration removed."
    exit 0
fi

LIBS_ONLY=""
[ "${1:-}" = "--libs-only" ] && LIBS_ONLY=1
KVER="$(uname -r)"
CAM_DEB="v4l2loopback-dkms linux-headers-$KVER"
[ -n "$LIBS_ONLY" ] && CAM_DEB=""
if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || true
    apt-get install -y -qq libxcb-cursor0 libxkbcommon-x11-0 libegl1 libgl1 libxcb-xinerama0 \
        libxcb-icccm4 libxcb-keysyms1 libxcb-shape0 libxcb-randr0 libxcb-render-util0 libxcb-image0 \
        libdbus-1-3 libfontconfig1 libgles2 libglib2.0-0 $CAM_DEB \
        || apt-get install -y -qq libxcb-cursor0 libegl1 libgl1 libgles2 libglib2.0-0 ${CAM_DEB%% *}
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q xcb-util-cursor libxkbcommon-x11 mesa-libEGL mesa-libGL mesa-libGLES glib2 xcb-util-wm \
        xcb-util-keysyms xcb-util-renderutil xcb-util-image || true
    # v4l2loopback comes from RPM Fusion on Fedora.
    if [ -n "$LIBS_ONLY" ]; then :
    elif ! dnf install -y -q v4l2loopback akmod-v4l2loopback 2>/dev/null; then
        . /etc/os-release
        dnf install -y -q \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${VERSION_ID}.noarch.rpm" \
            && dnf install -y -q v4l2loopback akmod-v4l2loopback && akmods --force 2>/dev/null || true
    fi
elif command -v pacman >/dev/null 2>&1; then
    if [ -n "$LIBS_ONLY" ]; then
        pacman -Sy --needed --noconfirm xcb-util-cursor libxkbcommon-x11 libglvnd glib2
    else
        pacman -Sy --needed --noconfirm xcb-util-cursor libxkbcommon-x11 libglvnd glib2 v4l2loopback-dkms linux-headers \
            || pacman -Sy --needed --noconfirm v4l2loopback-dkms
    fi
elif command -v zypper >/dev/null 2>&1; then
    CAM_SUSE="v4l2loopback-kmp-default"
    [ -n "$LIBS_ONLY" ] && CAM_SUSE=""
    zypper --non-interactive install xcb-util-cursor libxkbcommon-x11-0 Mesa-libEGL1 Mesa-libGLESv2-2 glib2 $CAM_SUSE || true
else
    echo "Unknown package manager: install v4l2loopback yourself." >&2
fi

[ -n "$LIBS_ONLY" ] && exit 0

cat > "$MODPROBE_CONF" <<EOF
# HandTrack virtual camera
options v4l2loopback devices=1 video_nr=$NR card_label="$LABEL" exclusive_caps=1
EOF
echo v4l2loopback > "$LOAD_CONF"

# Reload with our options (fails if another program is using a loopback camera).
modprobe -r v4l2loopback 2>/dev/null || true
if modprobe v4l2loopback; then
    echo "Camera ready: /dev/video$NR ($LABEL)"
else
    echo "" >&2
    echo "The v4l2loopback module could not be loaded." >&2
    if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
        echo "Secure Boot is on: the module has to be signed. See HOW-TO-INSTALL.txt, section" >&2
        echo "'Secure Boot', or turn Secure Boot off in the firmware settings." >&2
    else
        echo "Restart the computer and it will load automatically." >&2
    fi
    exit 2
fi

# Camera access for the user who ran sudo (most desktops grant it anyway).
if [ -n "${SUDO_USER:-}" ] && getent group video >/dev/null; then
    usermod -aG video "$SUDO_USER" 2>/dev/null || true
fi
exit 0
