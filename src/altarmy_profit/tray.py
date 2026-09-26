"""The tray uploader (`altarmy-profit-tray`, or the packaged `altarmy-profit-tray.exe`): the CLI watcher
(`watch.py`) in the Windows notification area, so players need no terminal or Python.

It watches both games' Alt Army and Auctionator SavedVariables and uploads the ones WoW rewrites, with the
API key from the site's Manage page (asked for on first run, kept in `~/.altarmy-profit/tray.json`). Its menu
shows the latest upload, and offers Upload now, Open site, Set API key, Start with Windows (the HKCU Run
key), the log and Quit. Windows only; the testable parts are in `tray_core.py`. Needs the `tray` extra.
"""

from __future__ import annotations

import contextlib
import os
import sys
import threading
import webbrowser
from pathlib import Path
from typing import Any

from . import tray_core, watch, wowfiles
from .tray_core import TrayConfig

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
RUN_VALUE = "altarmy-profit tray"
LOG_PATH = Path.home() / ".altarmy-profit" / "tray.log"
MUTEX = "Local\\altarmy-profit-tray"  # one tray per Windows user


class _Interrupt(Exception):
    """Raised from the watcher's sleep to stop it (quit) or restart it (new key)."""


class Tray:
    def __init__(self, config_path: Path = tray_core.CONFIG_PATH) -> None:
        self.config_path = config_path
        self.config = tray_core.load_config(config_path)
        self.status = tray_core.Status()
        self.wake = threading.Event()  # upload now, a new key, or quit
        self.quitting = threading.Event()
        self.restart = threading.Event()
        self.icon: Any = None

    # --- the watcher thread ---------------------------------------------------------------------
    def log(self, message: str) -> None:
        self.status.log(message)
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(self.status.history[-1] + "\n")
        if self.icon is not None:
            self.icon.update_menu()
            if self.status.problem:
                self.icon.notify(self.status.problem, "altarmy-profit")

    def _sleep(self, seconds: float) -> None:
        self.wake.wait(seconds)
        self.wake.clear()
        if self.quitting.is_set() or self.restart.is_set():
            raise _Interrupt

    def watch_loop(self) -> None:
        while not self.quitting.is_set():
            self.restart.clear()
            if self.config.key is None:
                self._ask_key()
                if self.config.key is None:
                    self.log("No API key: use Set API key… in this menu.")
                    self.wake.wait()
                    self.wake.clear()
                    continue
            cfg = self.config
            try:
                watch.run(wowfiles.WOW_ROOTS, cfg.server, cfg.key, log=self.log, sleep=self._sleep)
            except _Interrupt:
                continue
            # watch.run returns only when the server refused the key
            self._save(TrayConfig(cfg.server, None))

    def _save(self, config: TrayConfig) -> None:
        self.config = config
        tray_core.save_config(self.config_path, config)

    def _ask_key(self) -> None:
        """A small dialog for the API key (tkinter, in this thread)."""
        import tkinter
        from tkinter import simpledialog

        root = tkinter.Tk()
        root.withdraw()
        root.attributes("-topmost", True)
        key = simpledialog.askstring(
            "altarmy-profit",
            "Paste an API key from the site's Manage page (Upload automatically → Make a key).\n"
            f"Site: {self.config.server}",
            parent=root,
        )
        root.destroy()
        if key and key.strip():
            self._save(TrayConfig(self.config.server, key.strip()))
            self.log("API key saved.")

    # --- the menu (pystray's thread) ------------------------------------------------------------
    def _upload_now(self) -> None:
        self.wake.set()

    def _set_key(self) -> None:
        self._save(TrayConfig(self.config.server, None))
        self.restart.set()
        self.wake.set()

    def _open_site(self) -> None:
        webbrowser.open(self.config.server)

    def _show_log(self) -> None:
        if LOG_PATH.is_file() and sys.platform == "win32":
            os.startfile(LOG_PATH)

    def _quit(self) -> None:
        self.quitting.set()
        self.wake.set()
        if self.icon is not None:
            self.icon.stop()

    def run(self) -> None:
        import pystray

        item = pystray.MenuItem
        menu = pystray.Menu(
            item(lambda _: self.status.text, None, enabled=False),
            pystray.Menu.SEPARATOR,
            item("Upload now", lambda: self._upload_now(), default=True),
            item("Open site", lambda: self._open_site()),
            item("Set API key…", lambda: self._set_key()),
            item(
                "Start with Windows",
                lambda: set_autostart(not autostart_enabled()),
                checked=lambda _: autostart_enabled(),
            ),
            item("Show log", lambda: self._show_log()),
            pystray.Menu.SEPARATOR,
            item("Quit", lambda: self._quit()),
        )
        self.icon = pystray.Icon("altarmy-profit", _icon_image(), "altarmy-profit uploader", menu)
        threading.Thread(target=self.watch_loop, name="watcher", daemon=True).start()
        self.icon.run()


def _icon_image() -> Any:
    """A gold coin with an A."""
    from PIL import Image, ImageDraw

    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse((2, 2, 62, 62), fill=(214, 168, 46, 255), outline=(120, 86, 12, 255), width=4)
    draw.text((32, 33), "A", fill=(60, 40, 5, 255), anchor="mm", font_size=40)
    return img


# --- start with Windows (HKCU Run key) --------------------------------------------------------------
def autostart_enabled() -> bool:
    if sys.platform != "win32":
        return False
    import winreg

    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
            winreg.QueryValueEx(key, RUN_VALUE)
        return True
    except OSError:
        return False


def set_autostart(enabled: bool) -> None:
    if sys.platform != "win32":
        return
    import winreg

    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as key:
        if enabled:
            command = tray_core.autostart_command(sys.executable, frozen=bool(getattr(sys, "frozen", False)))
            winreg.SetValueEx(key, RUN_VALUE, 0, winreg.REG_SZ, command)
        else:
            with contextlib.suppress(FileNotFoundError):
                winreg.DeleteValue(key, RUN_VALUE)


def _single_instance() -> bool:
    """False if this Windows user already runs the tray (a named mutex, held until exit)."""
    if sys.platform != "win32":
        return True
    import ctypes

    kernel32 = ctypes.windll.kernel32
    kernel32.CreateMutexW(None, False, MUTEX)
    return int(kernel32.GetLastError()) != 183  # ERROR_ALREADY_EXISTS


def main() -> None:
    if sys.platform != "win32":
        sys.exit("The tray uploader is for Windows; elsewhere run `altarmy-profit watch`.")
    if not _single_instance():
        return
    Tray().run()


if __name__ == "__main__":
    main()
