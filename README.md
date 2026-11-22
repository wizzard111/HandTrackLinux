<div align="center">

<img src="src/handtrack/assets/icon.png" width="96" alt="HandTrack">

# HANDTRACK — Linux

**Gestures, gaze, face hiding and drawing in the air, right inside your calls.**
The "HandTrack Camera" virtual camera for Discord, Telegram, Zoom, Google Meet and OBS.

*In collaboration with [Claude](https://claude.ai).*

[⬇ Download](../../releases/latest) · [Step-by-step install](HOW-TO-INSTALL.txt) · [Windows](https://github.com/OWNER/HandTrackWindows) · [macOS](https://github.com/OWNER/HandTrackMac)

<img src="docs/screenshots/live.png" width="880" alt="HandTrack">

</div>

## Install

1. [Releases](../../releases/latest) → **handtrack-linux-x86_64.tar.gz** → "Extract Here".
2. Run **install.sh** (double-click; in GNOME, right-click → "Run as a Program").
   The files are already executable. Your password is asked once, for the virtual camera.
3. HandTrack appears in the application menu. In your call, pick the camera **HandTrack Camera**.

Step by step: [HOW-TO-INSTALL.txt](HOW-TO-INSTALL.txt). Uninstall: menu → "Uninstall HandTrack",
the `handtrack-uninstall` command or **uninstall.sh**.
Running the installer again only adds what is missing or changed.

Supported: Ubuntu 22.04+, Debian 12+, Fedora 39+, Mint 21+, Arch, openSUSE (x86_64 and ARM64).
The camera is the v4l2loopback kernel module from your distribution; with Secure Boot it has to be signed (see the guide).

> From the code (Code → Download ZIP) the installer sets up an isolated Python 3.12 and the libraries
> in `~/.local/lib/handtrack`; the system Python is not touched.

## Repository layout

```
install.sh / uninstall.sh   installer and uninstaller
HOW-TO-INSTALL.txt          step-by-step guide
src/handtrack/              the program (same code as on Windows/macOS)
packaging/linux/            vcam-setup.sh (camera + Qt libraries), release build, PyInstaller spec
tests/                      tests
```

Development: `pip install -r packaging/requirements-dev.txt`, `PYTHONPATH=src python -m handtrack`,
`python -m pytest`; release: `packaging/linux/build.sh`.

## License

[MIT](LICENSE). Third-party components: [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).
