#!/usr/bin/env python3
"""Release one part of Alt Army from the monorepo root: python release.py [--dry-run]

Asks which to release, checks the checkout (on main, clean, not behind origin), then:
  addon   bumps the version in addon/AltArmy_TBC/AltArmy_TBC.toc, Core.lua, package.json and package-lock.json,
          writes addon/CHANGELOG.txt from the notes you type (the GitHub Release's and CurseForge's changelog;
          removed when you give none), commits "vX.Y.Z", tags addon-vX.Y.Z and pushes main and the tag:
          .github/workflows/addon-release.yml uploads to CurseForge and Wago and makes the repository's Latest
          release.
  site    prod: pushes main; site-check then site-deploy deploy whatever changed under site/. When nothing
          under site/ is left to push, runs the site-deploy workflow by hand instead (Run workflow, prod).
          staging: runs site-deploy by hand for staging, from main's head.
  sync    tags sync-vX.Y.Z (the version lives in the tag alone: scripts/build_sync.py stamps it into the exe)
          and pushes it (and main, so the tagged commit is on main): sync-release.yml builds the exe and
          refreshes the rolling sync-latest release.
Then it finds the workflow run and can watch it (gh run watch). Needs git and gh (signed in). Standard library only.
--dry-run prints the commands that would change anything instead of running them.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = "ntower/altarmy"
ADDON = ROOT / "addon"
TOC = ADDON / "AltArmy_TBC" / "AltArmy_TBC.toc"
CORE = ADDON / "AltArmy_TBC" / "Core.lua"
PACKAGE = ADDON / "package.json"
LOCK = ADDON / "package-lock.json"
CHANGELOG = ADDON / "CHANGELOG.txt"
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")

DRY_RUN = False


def run(*cmd: str, capture: bool = True, check: bool = True) -> str:
    """Run a command that changes nothing (always runs, even with --dry-run)."""
    result = subprocess.run(cmd, cwd=ROOT, capture_output=capture, text=True, encoding="utf-8", check=False)
    if check and result.returncode != 0:
        sys.exit(f"{' '.join(cmd)} failed:\n{(result.stderr or result.stdout or '').strip()}")
    return (result.stdout or "").strip() if capture else ""


def act(*cmd: str) -> None:
    """Run a command that changes the checkout or the remote, or print it with --dry-run."""
    if DRY_RUN:
        print("  would run:", " ".join(cmd))
        return
    print("  $", " ".join(cmd))
    run(*cmd, capture=False)


def write(path: Path, text: str) -> None:
    """Write `text` as is (no newline translation)."""
    if DRY_RUN:
        print(f"  would write {path.relative_to(ROOT)}")
        return
    path.write_text(text, encoding="utf-8", newline="")


def ask(prompt: str, default: str = "") -> str:
    hint = f" [{default}]" if default else ""
    answer = input(f"{prompt}{hint}: ").strip()
    return answer or default


def confirm(prompt: str, default: bool = True) -> bool:
    answer = ask(prompt + (" (Y/n)" if default else " (y/N)")).lower()
    return default if not answer else answer in ("y", "yes")


def bump(version: str, part: str) -> str:
    major, minor, patch = (int(n) for n in version.split("."))
    if part == "major":
        return f"{major + 1}.0.0"
    if part == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def choose_version(current: str, what: str) -> str:
    """Offer patch, minor and major bumps of `current`, or a typed version."""
    options = {k: bump(current, k) for k in ("patch", "minor", "major")}
    print(f"{what} is {current}. Next:")
    for i, (part, version) in enumerate(options.items(), 1):
        print(f"  {i}. {version} ({part})")
    while True:
        answer = ask("Version (number or X.Y.Z)", "1")
        if answer in ("1", "2", "3"):
            return list(options.values())[int(answer) - 1]
        if VERSION_RE.match(answer):
            return answer
        print("  three numbers, e.g. 2.3.0")


def check_checkout() -> int:
    """On main, clean, fetched and not behind origin. Returns how many commits main is ahead."""
    if run("git", "rev-parse", "--abbrev-ref", "HEAD") != "main":
        sys.exit("release from main.")
    if run("git", "status", "--porcelain", "--untracked-files=no"):
        sys.exit("the working tree has uncommitted changes; commit or stash them first.")
    run("git", "fetch", "--quiet", "--tags", "origin")
    counts = run("git", "rev-list", "--left-right", "--count", "origin/main...main").split()
    behind, ahead = (int(n) for n in counts)
    if behind:
        sys.exit(f"main is {behind} commit(s) behind origin/main; pull first.")
    if ahead:
        print(f"main is {ahead} commit(s) ahead of origin/main; they will be pushed with the release.")
    return ahead


def tag_exists(tag: str) -> bool:
    return bool(run("git", "tag", "-l", tag)) or bool(
        run("git", "ls-remote", "--tags", "origin", f"refs/tags/{tag}")
    )


def replace_once(path: Path, pattern: str, replacement: str, count: int = 1) -> None:
    """Replace `pattern` (exactly `count` times) in `path`, keeping the file's own line endings."""
    with path.open(encoding="utf-8", newline="") as f:
        raw = f.read()
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")
    new, n = re.subn(pattern, replacement, text, flags=re.MULTILINE)
    if n != count:
        sys.exit(f"{path.relative_to(ROOT)}: expected {count} match(es) of {pattern!r}, found {n}")
    write(path, new.replace("\n", "\r\n") if crlf else new)


def release_notes() -> list[str]:
    print(
        "Release notes for CurseForge, Wago and the GitHub Release (one line each; an empty line ends them;"
    )
    print("none at all means 'See repository for changes.'):")
    lines: list[str] = []
    while True:
        line = input("  > ").rstrip()
        if not line:
            return lines
        lines.append(line)


def find_run(workflow: str, ref: str) -> tuple[str, str] | None:
    """The newest run of `workflow` for `ref` (a branch or tag), once GitHub has queued it."""
    jq = '.[0] | "\\(.databaseId) \\(.url)"'
    for _ in range(12):
        time.sleep(5)
        out = run(
            "gh",
            "run",
            "list",
            "--repo",
            REPO,
            "--workflow",
            workflow,
            "--branch",
            ref,
            "--limit",
            "1",
            "--json",
            "databaseId,url",
            "--jq",
            jq,
            check=False,
        )
        if out and not out.startswith("null"):
            run_id, url = out.split(" ", 1)
            return run_id, url
    return None


def watch(workflow: str, ref: str) -> None:
    if DRY_RUN:
        print(f"  would wait for the {workflow} run on {ref} and offer to watch it")
        return
    print(f"waiting for the {workflow} run...")
    found = find_run(workflow, ref)
    if not found:
        print(f"no {workflow} run showed up yet: https://github.com/{REPO}/actions/workflows/{workflow}.yml")
        return
    run_id, url = found
    print(f"  {url}")
    if confirm("Watch it here?"):
        subprocess.run(["gh", "run", "watch", "--repo", REPO, "--exit-status", run_id], cwd=ROOT, check=False)


def release_addon() -> None:
    check_checkout()
    current = re.search(r"^## Version: (\S+)", TOC.read_text(encoding="utf-8"), re.MULTILINE)
    if not current:
        sys.exit(f"no '## Version:' in {TOC}")
    version = choose_version(current.group(1), "The addon")
    tag = f"addon-v{version}"
    if tag_exists(tag):
        sys.exit(f"tag {tag} already exists.")
    notes = release_notes()
    print(f"\nBumping {current.group(1)} -> {version}, committing, tagging {tag} and pushing.")
    if not confirm("Go ahead?"):
        sys.exit("nothing done.")
    old = re.escape(current.group(1))
    replace_once(TOC, rf"^## Version: {old}$", f"## Version: {version}")
    replace_once(CORE, rf'^local ADDON_VERSION = "{old}"$', f'local ADDON_VERSION = "{version}"')
    replace_once(PACKAGE, rf'^  "version": "{old}",$', f'  "version": "{version}",')
    replace_once(LOCK, rf'^(\s+)"version": "{old}"(,?)$', rf'\g<1>"version": "{version}"\g<2>', count=2)
    paths = [TOC, CORE, PACKAGE, LOCK]
    if notes:
        write(CHANGELOG, "\n".join(notes) + "\n")
        paths.append(CHANGELOG)
    elif run("git", "ls-files", str(CHANGELOG)):  # last release's notes: the workflow's placeholder instead
        act("git", "rm", "--quiet", "--force", str(CHANGELOG))
    elif CHANGELOG.exists():  # an untracked leftover the workflow would publish
        sys.exit(f"remove the untracked {CHANGELOG.relative_to(ROOT)} or give release notes.")
    act("git", "add", *(str(p) for p in paths))
    act("git", "commit", "--quiet", "-m", f"v{version}")
    act("git", "tag", tag)
    act("git", "push", "origin", "main", tag)
    watch("addon-release", tag)


def release_site(environment: str) -> None:
    ahead = check_checkout()
    touches_site = bool(ahead) and bool(run("git", "diff", "--name-only", "origin/main..main", "--", "site"))
    if environment == "prod":
        if touches_site:
            print("Pushing main: site-check runs, then site-deploy deploys prod.")
            if not confirm("Go ahead?"):
                sys.exit("nothing done.")
            act("git", "push", "origin", "main")
            watch("site-check", "main")
            print(
                "site-deploy follows when site-check passes: "
                f"https://github.com/{REPO}/actions/workflows/site-deploy.yml"
            )
            return
        if ahead:
            print("The unpushed commits touch nothing under site/, so pushing alone would not deploy.")
        print("Nothing new under site/ to push: running site-deploy for prod from main's head.")
    else:
        print("Running site-deploy for staging from main's head.")
    if not confirm("Go ahead?"):
        sys.exit("nothing done.")
    if ahead:
        act("git", "push", "origin", "main")
    act(
        "gh",
        "workflow",
        "run",
        "site-deploy",
        "--repo",
        REPO,
        "--ref",
        "main",
        "-f",
        f"environment={environment}",
    )
    watch("site-deploy", "main")


def release_sync() -> None:
    ahead = check_checkout()
    versions = sorted(
        (
            t.removeprefix("sync-v")
            for t in run("git", "tag", "-l", "sync-v*").split()
            if VERSION_RE.match(t.removeprefix("sync-v"))
        ),
        key=lambda v: tuple(int(n) for n in v.split(".")),
    )
    version = choose_version(versions[-1] if versions else "0.0.0", "Alt Army Sync")
    tag = f"sync-v{version}"
    if tag_exists(tag):
        sys.exit(f"tag {tag} already exists.")
    print(f"\nTagging main's head {tag} and pushing{' main and' if ahead else ''} the tag.")
    if not confirm("Go ahead?"):
        sys.exit("nothing done.")
    act("git", "tag", tag)
    act("git", "push", "origin", *(["main"] if ahead else []), tag)
    watch("sync-release", tag)


def main() -> None:
    global DRY_RUN
    parser = argparse.ArgumentParser(description="Release the addon, the site or Alt Army Sync.")
    parser.add_argument("--dry-run", action="store_true", help="print what would change instead of doing it")
    DRY_RUN = parser.parse_args().dry_run
    if DRY_RUN:
        print("(dry run: nothing is changed or pushed)")
    print("What do you want to release?")
    print("  1. addon         (CurseForge, Wago, GitHub Release)")
    print("  2. site, prod    (push main; site-check then site-deploy)")
    print("  3. site, staging (site-deploy by hand from main's head)")
    print("  4. sync          (Alt Army Sync, the Windows exe)")
    choice = ask("Choice", "1")
    if choice == "1":
        release_addon()
    elif choice == "2":
        release_site("prod")
    elif choice == "3":
        release_site("staging")
    elif choice == "4":
        release_sync()
    else:
        sys.exit("no such choice.")


if __name__ == "__main__":
    main()
