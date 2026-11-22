<div align="center">

<img src="src/handtrack/assets/icon.png" width="96" alt="HandTrack">

# HANDTRACK — Linux

**Gestures, gaze, face hiding and drawing in the air, right inside your calls.**
The "HandTrack Camera" virtual camera for Discord, Telegram, Zoom, Google Meet and OBS.

*In collaboration with [Claude](https://claude.ai).*

[⬇ Download](../../releases/latest) · [Step-by-step install](HOW-TO-INSTALL.txt) · [Windows](https://github.com/wizzard111/HandTrackWindows) · [macOS](https://github.com/wizzard111/HandTrackMac)

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

Development: `uv pip install -r packaging/requirements-dev.txt --override packaging/overrides.txt`, `PYTHONPATH=src python -m handtrack`,
`python -m pytest`; release: `packaging/linux/build.sh`.

## Performance

Measured with [`packaging/benchmark.py`](packaging/benchmark.py): the real app runs each situation for
20 s in a fresh process while the script samples its CPU and memory once a second. To compare
operating systems on equal terms, a 1280×720 video at 30 FPS (an empty room, so hand and face
detection keep searching: the costly case) stands in for the webcam.

Machine: AMD Ryzen 5 5600X (6 cores, 12 threads), 16 GB RAM. HandTrack 8.2.0, Python 3.12.
CPU is in % of **one** core, summed over all of the app's threads; divide by 12 for the share of the
whole processor. RAM is the resident set (working set on Windows; includes shared libraries), USS is
memory used by HandTrack alone.

| Situation | Windows 11: CPU | RAM | USS | Linux (Debian 13): CPU | RAM | USS |
|---|---:|---:|---:|---:|---:|---:|
| Window open, camera off | 2.1 % | 202 MB | 136 MB | 0.9 % | 241 MB | 227 MB |
| In the tray, camera off | 1.4 % | 202 MB | 135 MB | — | — | — |
| Camera on | 36 % | 234 MB | 162 MB | 30 % | 288 MB | 274 MB |
| Camera on, window in the tray | 25 % | 233 MB | 164 MB | — | — | — |
| Camera on + Hide face | 35 % | 232 MB | 160 MB | 29 % | 285 MB | 271 MB |
| In a call: Hide face + virtual camera, read by a call app | 39 % | 244 MB | 169 MB | — | — | — |

With the real webcam (Windows, Lenovo FHD webcam, 1280×720 at ~30 FPS) the numbers depend on what is
in view: 55–85 % of one core (5–7 % of the whole processor), 250–280 MB RAM. Reading the camera
itself costs about 13 % of a core at 1280×720 and 30 % at 1920×1080 (the MJPG decoding in Windows'
DirectShow), so 1280×720, the default, is the economical choice; most call apps send 1280×720 anyway.
The camera starts in about 0.6 s.
Linux was measured under WSL2 (WSLg); "—" means the situation needs a tray or the Windows camera
driver, which WSL lacks. macOS has not been measured.

How it stays light:

- Idle costs almost nothing: no timers repaint the window; the preview, status tags and gaze map
  redraw only when something changes. Before 8.2 an idle window took 11 % of a core. The small
  sidebar animation (about 1 % of a core, 15 FPS) pauses while the window is minimised or in the
  tray, and can be switched off in Settings.
- Detection slows down while nothing is in view (hands 15, faces 10 checks a second) and returns to
  full rate the moment a hand or face appears. Processing runs on its own thread, the neural
  networks asynchronously; the interface never waits for the camera.
- The camera format is set once when it opens (DirectShow rebuilt its capture graph for every
  setting: the first frame came after 2.2 s, now after 0.6 s).
- Every frame is processed once: the AFK screen is rendered once and copied, the preview is
  converted to Qt's native format on the video thread and is not prepared while hidden, stickers
  are blended with integer maths, and the drawing goes straight into the frame.
- No idle thread pools: OpenCV runs single-threaded and numpy's OpenBLAS uses one thread (its
  per-core buffers alone were ~350 MB of private memory).
- Only what is needed is installed: the headless OpenCV, without mediapipe's GUI OpenCV,
  matplotlib and audio packages. The face-hiding sound is played by the operating system, with no
  audio library in the app.

Reproduce: `PYTHONPATH=src python packaging/benchmark.py --video any-video.mp4`
(or `--video camera` for the webcam).

## License

[MIT](LICENSE). Third-party components: [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).
