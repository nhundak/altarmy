"""Alt Army Sync (`altarmy-sync`, or the packaged `altarmy-sync.exe`): the CLI watcher
(`watch.py`) in the Windows notification area, so players need no terminal or Python.

It watches both games' Alt Army and Auctionator SavedVariables and uploads the ones WoW rewrites, signed in
to the user's site account (`signin`): on first run a dialog signs in with an email and password, or creates
an account; only Firebase's refresh token is kept, in `~/.altarmy/sync.json`. Its menu shows who is
signed in and the latest upload, and offers Upload now, Open site, Sign in / Sign out, Start with Windows
(the HKCU Run key), the log and Quit. The packaged exe checks GitHub for a newer release every few hours,
then notifies once and adds Update available to the menu (it does not update itself). It uploads to the
live site; `--staging` (or `--server URL`) picks another, with its own settings, log and Start with Windows
entry (`tray_core.Target`). Windows only; the testable parts are in `tray_core.py`. Needs the `tray` extra.
"""

from __future__ import annotations

import contextlib
import dataclasses
import os
import sys
import threading
import webbrowser
from typing import Any

from . import signin, tray_core, watch, wowfiles
from .tray_core import Target

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
UPDATE_FIRST_CHECK = 60  # seconds after start
UPDATE_EVERY = 6 * 3600


class _Interrupt(Exception):
    """Raised from the watcher's sleep to stop it (quit) or restart it (signed out from the menu)."""


class Tray:
    def __init__(self, target: Target = tray_core.PROD) -> None:
        self.target = target
        self.config = tray_core.load_config(target.config_path)
        self.status = tray_core.Status()
        self.wake = threading.Event()  # upload now, a sign-in or sign-out, or quit
        self.quitting = threading.Event()
        self.restart = threading.Event()
        self.saving = threading.Lock()  # the watcher and the update check both save the settings
        self.update: tray_core.Release | None = None
        self.icon: Any = None

    # --- the watcher thread ---------------------------------------------------------------------
    def log(self, message: str) -> None:
        self.status.log(message)
        log_path = self.target.log_path
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("a", encoding="utf-8") as f:
            f.write(self.status.history[-1] + "\n")
        if self.icon is not None:
            self.icon.update_menu()
            if self.status.problem:
                self.icon.notify(self.status.problem, self.target.title)

    def _sleep(self, seconds: float) -> None:
        self.wake.wait(seconds)
        self.wake.clear()
        if self.quitting.is_set() or self.restart.is_set():
            raise _Interrupt

    def watch_loop(self) -> None:
        while not self.quitting.is_set():
            self.restart.clear()
            try:
                creds = self._credentials()
            except signin.Unreachable as e:
                self.log(f"Upload failed (could not reach the site: {e}); retrying.")
                self._wait(60)
                continue
            if creds is None:
                self.log("Not signed in: use Sign in… in this menu.")
                self._wait(None)
                continue
            try:
                watch.run(wowfiles.WOW_ROOTS, self.target.server, creds, log=self.log, sleep=self._sleep)
            except _Interrupt:
                continue
            # watch.run returns only when the sign-in stopped working
            self._save(email=None, refresh_token=None)

    def _wait(self, seconds: float | None) -> None:
        """Wait for the menu (or `seconds`), without raising."""
        self.wake.wait(seconds)
        self.wake.clear()

    def _save(self, **changes: str | None) -> None:
        """Change and save the settings (`TrayConfig`'s fields), keeping the rest."""
        with self.saving:
            self.config = dataclasses.replace(self.config, **changes)
            tray_core.save_config(self.target.config_path, self.config)
        if self.icon is not None:
            self.icon.update_menu()

    def _remember(self, session: signin.Session) -> None:
        self._save(email=session.email, refresh_token=session.refresh_token)

    # --- the update check thread ----------------------------------------------------------------
    def update_loop(self) -> None:
        """Ask GitHub for a newer release now and then; tell the user once per version."""
        if self.quitting.wait(UPDATE_FIRST_CHECK):
            return
        while True:
            release = tray_core.check_for_update(tray_core.VERSION)
            if release is not None:
                self.update = release
                if self.config.notified_version != release.version:
                    self._save(notified_version=release.version)
                    self.log(f"Alt Army Sync {release.version} is available: {release.url}")
                    if self.icon is not None:
                        self.icon.notify(
                            f"Version {release.version} is available: use Update available in the menu.",
                            self.target.title,
                        )
                elif self.icon is not None:
                    self.icon.update_menu()
            if self.quitting.wait(UPDATE_EVERY):
                return

    def _credentials(self) -> signin.Credentials | None:
        """The saved sign-in, else the sign-in dialog's; None if the user closed it."""
        config = signin.fetch_config(self.target.server)
        cfg = self.config
        if cfg.email is not None and cfg.refresh_token is not None:
            return signin.Credentials(config, cfg.email, cfg.refresh_token, on_change=self._remember)
        session = self._sign_in_dialog(config)
        if session is None:
            return None
        self._remember(session)
        self.log(f"Signed in as {session.email}.")
        return signin.Credentials.of(config, session, on_change=self._remember)

    def _sign_in_dialog(self, config: signin.AuthConfig) -> signin.Session | None:
        """Email and password (tkinter, in this thread): sign in, or tick "Create a new account"."""
        import tkinter as tk
        from tkinter import ttk

        root = tk.Tk()
        root.title(f"{self.target.title}: sign in")
        root.attributes("-topmost", True)
        root.resizable(False, False)
        frame = ttk.Frame(root, padding=16)
        frame.grid()
        intro = (
            "Sign in with your Alt Army account, the one you use on the site.\n"
            "No account yet? Tick Create a new account. It starts empty: to keep what you have set up in\n"
            "a browser, create the account on the site instead (Sign in, then Create account)."
        )
        ttk.Label(frame, text=intro, justify="left").grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 12)
        )
        email, password, confirm, create = tk.StringVar(), tk.StringVar(), tk.StringVar(), tk.BooleanVar()
        ttk.Label(frame, text="Email").grid(row=1, column=0, sticky="w")
        email_entry = ttk.Entry(frame, textvariable=email, width=40)
        email_entry.grid(row=1, column=1, pady=2)
        ttk.Label(frame, text="Password").grid(row=2, column=0, sticky="w")
        ttk.Entry(frame, textvariable=password, show="•", width=40).grid(row=2, column=1, pady=2)
        confirm_label = ttk.Label(frame, text="Password again")
        confirm_entry = ttk.Entry(frame, textvariable=confirm, show="•", width=40)
        error = ttk.Label(frame, foreground="#b00020", wraplength=420, justify="left")
        error.grid(row=5, column=0, columnspan=2, sticky="w", pady=(8, 0))
        buttons = ttk.Frame(frame)
        buttons.grid(row=6, column=0, columnspan=2, sticky="e", pady=(12, 0))
        submit = ttk.Button(buttons, text="Sign in")
        submit.grid(row=0, column=1, padx=(8, 0))
        ttk.Button(buttons, text="Cancel", command=root.destroy).grid(row=0, column=2, padx=(8, 0))
        result: list[signin.Session] = []

        def toggle() -> None:
            if create.get():
                confirm_label.grid(row=3, column=0, sticky="w")
                confirm_entry.grid(row=3, column=1, pady=2)
                submit.configure(text="Create account")
            else:
                confirm_label.grid_remove()
                confirm_entry.grid_remove()
                submit.configure(text="Sign in")

        def go() -> None:
            new = create.get()
            problem = tray_core.form_problem(email.get(), password.get(), confirm.get() if new else None)
            if problem is None:
                error.configure(text="Signing in…")
                root.update_idletasks()
                act = signin.sign_up if new else signin.sign_in
                try:
                    result.append(act(config, email.get(), password.get()))
                except (signin.SignInError, signin.Unreachable) as e:
                    problem = str(e)
            if problem is not None:
                error.configure(text=problem)
                return
            root.destroy()

        ttk.Checkbutton(frame, text="Create a new account", variable=create, command=toggle).grid(
            row=4, column=1, sticky="w", pady=(4, 0)
        )
        submit.configure(command=go)
        root.bind("<Return>", lambda _: go())
        root.bind("<Escape>", lambda _: root.destroy())
        email_entry.focus_set()
        root.mainloop()
        return result[0] if result else None

    # --- the menu (pystray's thread) ------------------------------------------------------------
    def _upload_now(self) -> None:
        self.wake.set()

    def _sign_in_or_out(self) -> None:
        """Signed in: forget the sign-in (the dialog then asks again). Signed out: show the dialog now."""
        if self.config.signed_in:
            self._save(email=None, refresh_token=None)
            self.log("Signed out.")
            self.restart.set()
        self.wake.set()

    def _open_site(self) -> None:
        webbrowser.open(self.target.server)

    def _open_update(self) -> None:
        if self.update is not None:
            webbrowser.open(self.update.url)

    def _show_log(self) -> None:
        if self.target.log_path.is_file() and sys.platform == "win32":
            os.startfile(self.target.log_path)

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
            item(
                lambda _: f"Signed in as {self.config.email}" if self.config.signed_in else "Not signed in",
                None,
                enabled=False,
            ),
            item(
                lambda _: f"Update available: {self.update.version}…" if self.update else "",
                lambda: self._open_update(),
                visible=lambda _: self.update is not None,
            ),
            pystray.Menu.SEPARATOR,
            item("Upload now", lambda: self._upload_now(), default=True),
            item("Open site", lambda: self._open_site()),
            item(
                lambda _: "Sign out" if self.config.signed_in else "Sign in…", lambda: self._sign_in_or_out()
            ),
            item(
                "Start with Windows",
                lambda: set_autostart(self.target, not autostart_enabled(self.target)),
                checked=lambda _: autostart_enabled(self.target),
            ),
            item("Show log", lambda: self._show_log()),
            pystray.Menu.SEPARATOR,
            item("Quit", lambda: self._quit()),
        )
        title = f"{self.target.title} {tray_core.VERSION}"
        self.icon = pystray.Icon(self.target.run_value, _icon_image(), title, menu)
        threading.Thread(target=self.watch_loop, name="watcher", daemon=True).start()
        if tray_core.parse_version(tray_core.VERSION) is not None:  # not from source
            threading.Thread(target=self.update_loop, name="updates", daemon=True).start()
        self.icon.run()


def _icon_image() -> Any:
    """A gold coin with an A. The A is drawn with lines, not a font, so the exe needs no FreeType
    (scripts/build_sync.py leaves Pillow's font, colour-management and image-format extensions out)."""
    from PIL import Image, ImageDraw

    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse((2, 2, 62, 62), fill=(214, 168, 46, 255), outline=(120, 86, 12, 255), width=4)
    ink = (60, 40, 5, 255)
    draw.line([(20, 50), (32, 14), (44, 50)], fill=ink, width=7, joint="curve")
    draw.line([(25, 38), (39, 38)], fill=ink, width=5)
    return img


# --- start with Windows (HKCU Run key) --------------------------------------------------------------
def autostart_enabled(target: Target) -> bool:
    if sys.platform != "win32":
        return False
    import winreg

    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
            winreg.QueryValueEx(key, target.run_value)
        return True
    except OSError:
        return False


def set_autostart(target: Target, enabled: bool) -> None:
    if sys.platform != "win32":
        return
    import winreg

    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as key:
        if enabled:
            frozen = bool(getattr(sys, "frozen", False))
            command = tray_core.autostart_command(sys.executable, frozen=frozen, args=target.args)
            winreg.SetValueEx(key, target.run_value, 0, winreg.REG_SZ, command)
        else:
            with contextlib.suppress(FileNotFoundError):
                winreg.DeleteValue(key, target.run_value)


def _single_instance(target: Target) -> bool:
    """False if this Windows user already runs the tray for `target` (a named mutex, held until exit)."""
    if sys.platform != "win32":
        return True
    import ctypes

    kernel32 = ctypes.windll.kernel32
    kernel32.CreateMutexW(None, False, target.mutex)
    return int(kernel32.GetLastError()) != 183  # ERROR_ALREADY_EXISTS


def main() -> None:
    if sys.platform != "win32":
        sys.exit("Alt Army Sync is for Windows; elsewhere run `altarmy-site watch`.")
    target = tray_core.parse_args(sys.argv[1:])
    signin.move_old_settings()
    if not _single_instance(target):
        return
    Tray(target).run()


if __name__ == "__main__":
    main()
