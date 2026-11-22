# PyInstaller spec — Linux, one-folder. Run via packaging/linux/build.sh.
import os

ROOT = os.path.abspath(os.path.join(SPECPATH, "..", ".."))
DRIVER = False
EXTRA_DATAS = [(os.path.join(ROOT, "packaging", "linux", "vcam-setup.sh"), "driver")]
EXTRA_EXCLUDES = ["pyvirtualcam"]
HIDDEN_IMPORTS = ["pyautogui"]  # imported lazily, invisible to the analysis
exec(open(os.path.join(ROOT, "packaging", "common.spec.py"), encoding="utf-8").read())

exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name="handtrack", console=False, strip=False, upx=False)
coll = COLLECT(exe, a.binaries, a.datas, name="handtrack", strip=False, upx=False)
