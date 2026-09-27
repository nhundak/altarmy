"""Command line interface: the site's jobs (ingest, migrate, prune, merge, ahledger), `serve` (the API and
built front end, for development) and `watch` (uploads the addon files to a server).

`--game-version` (tbc | forever) picks the game's data and wago.tools product. Every version shares one
database: `--db` (a SQLite file), else `DATABASE_URL`, else data/altarmy-profit.sqlite.
"""

from __future__ import annotations

import argparse
import getpass
import os
import sys
from pathlib import Path

from . import ahledger, db, ingest, merge, prices, service, signin, versions, watch, wowfiles
from .versions import GameVersion


def _version(args: argparse.Namespace) -> GameVersion:
    return versions.get(args.game_version)


def _database(args: argparse.Namespace) -> db.Database:
    """`--db`, else DATABASE_URL, else the default SQLite file (absolute, so the server's threads agree)."""
    if args.db:
        return db.Database(db.sqlite_url(Path(args.db).resolve()))
    url = db.default_url()
    return db.Database(url if url != db.sqlite_url(db.DEFAULT_DB) else db.sqlite_url(db.DEFAULT_DB.resolve()))


def cmd_ingest(args: argparse.Namespace) -> None:
    v = _version(args)
    if args.only_if_new:  # the hosted daily job: the newest build, unless it is already loaded
        with args.database.begin() as conn:
            build, updated, stats = service.update_game_data(conn, v, Path(args.cache), only_if_new=True)
        print(
            f"Ingested {v.label} build {build}: {stats}"
            if updated
            else f"{v.label} build {build} already loaded."
        )
        return
    build = args.build or v.default_build
    if build == "latest":
        build = ingest.latest_build(v.wago_product)
    with args.database.begin() as conn:
        stats = ingest.update(conn, v.key, build, Path(args.cache), v.disenchant_csv, v.vendor_csv)
    print(f"Ingested {v.label} build {build}: {stats}")


def cmd_migrate(args: argparse.Namespace) -> None:
    """Migrate to the newest revision (a hosted deploy runs this once, before the new service starts)."""
    with args.database.begin() as conn:
        db.upgrade(conn)
        db.register_versions(conn)
        revision = db.current_revision(conn)
    print(f"Database at revision {revision}.")


def cmd_prune(args: argparse.Namespace) -> None:
    with args.database.begin() as conn:
        prices.prune(conn)
    print(f"Pruned price observations older than {prices.KEEP_DAYS} days.")


def cmd_merge(args: argparse.Namespace) -> None:
    with args.database.begin() as conn:
        changed = merge.merge(conn)
        observations = merge.observation_count(conn)
    print(
        f"Merged {len(changed)} auction houses of every game version ({sum(changed.values())} changed); "
        f"{observations} price observations stored."
    )


def cmd_ahledger(args: argparse.Namespace) -> None:
    """Poll AHledger's markets of every version (an hourly job), one transaction per market."""
    client = ahledger.Client.from_env()
    wanted = [(v.key, m) for v in versions.VERSIONS.values() for m in ahledger.markets(v.key)]
    failed = 0
    try:
        served = client.markets()
    except (ahledger.AHledgerError, ValueError) as e:
        sys.exit(f"AHledger: {e}")
    for game_version, market in wanted:
        if market.id not in served:
            print(f"{market.id}: not an AHledger market (any more?)")
            failed += 1
            continue
        try:
            with args.database.begin() as conn:
                print(ahledger.poll_market(conn, game_version, market, client).summary)
        except (ahledger.AHledgerError, ValueError) as e:
            print(f"{market.id}: {e}")
            failed += 1
    with args.database.begin() as conn:
        prices.prune(conn)
    print(f"{client.requests} requests to AHledger.")
    if failed:
        sys.exit(f"{failed} of {len(wanted)} AHledger markets failed.")


def cmd_serve(args: argparse.Namespace) -> None:
    """The API (and the built front end, if any) on one port: `npm run dev` runs it behind Vite, signed in
    against the Firebase Auth emulator. Migrates the database first."""
    try:
        import uvicorn

        from .api import DEFAULT_DIST, create_app
    except ImportError:
        sys.exit('The server needs FastAPI, uvicorn and firebase-admin: pip install -e ".[ui]"')
    try:
        app = create_app(versions.VERSIONS, database=args.database)
    except ValueError as e:
        sys.exit(str(e))
    with args.database.begin() as conn:
        for v in versions.VERSIONS.values():
            if db.count_rows(conn, "recipes", v.key) == 0:
                flag = "" if v.key == versions.DEFAULT_VERSION else f" --game-version {v.key}"
                print(f"No {v.label} game data yet: run `altarmy-profit{flag} ingest`.")
    if not (DEFAULT_DIST / "index.html").is_file():
        print(f"Front end not built ({DEFAULT_DIST} missing): `npm run dev` serves it through Vite instead.")
    print(f"altarmy-profit API on http://{args.host}:{args.port} (Ctrl+C to stop)")
    uvicorn.run(app, host=args.host, port=args.port)


def _ask(prompt: str, env: str, secret: bool = False) -> str:
    """A value from the environment (for running unattended), else asked for on the terminal."""
    value = os.environ.get(env)
    if value:
        return value
    return getpass.getpass(prompt) if secret else input(prompt)


def watch_credentials(
    server: str,
    path: Path,
    *,
    fresh: bool = False,
    create: bool = False,
    transport: signin.Transport = signin.urllib_transport,
) -> signin.Credentials:
    """The watcher's sign-in to `server`: the one saved in `path`, else (or with `fresh`) an email and
    password asked for once (`create`: a new account). Only the refresh token is saved."""
    config = signin.fetch_config(server, transport)

    def remember(session: signin.Session) -> None:
        signin.save(path, server, session)

    saved = None if fresh or create else signin.load_saved(path, server)
    if saved is not None:
        email, token = saved
        return signin.Credentials(config, email, token, transport, on_change=remember)
    email = _ask("Email: ", "ALTARMY_EMAIL")
    password = _ask("Password: ", "ALTARMY_PASSWORD", secret=True)
    if create:
        if _ask("Password again: ", "ALTARMY_PASSWORD", secret=True) != password:
            raise signin.SignInError("The passwords don't match.")
        session = signin.sign_up(config, email, password, transport)
    else:
        session = signin.sign_in(config, email, password, transport)
    remember(session)
    print(f"Signed in as {session.email}.")
    return signin.Credentials.of(config, session, transport=transport, on_change=remember)


def cmd_watch(args: argparse.Namespace) -> None:
    """Upload the addon files to a server whenever WoW rewrites them (no local database)."""
    roots = [Path(r) for r in args.wow_root] if args.wow_root else wowfiles.WOW_ROOTS
    state = Path(args.state)
    auth_path = Path(args.auth)
    server = args.server.rstrip("/")
    found = watch.find_files(roots)
    if not found:
        sys.exit(
            f"No Alt Army or Auctionator files under {', '.join(str(r) for r in roots)}; pass --wow-root."
        )
    try:
        creds = watch_credentials(server, auth_path, fresh=args.sign_in, create=args.create_account)
        print(f"Watching {len(found)} files for {server} as {creds.email} (Ctrl+C to stop).")
        if args.once:
            if not watch.sync_once(roots, server, creds, state):
                print("Nothing changed since the last upload.")
        else:
            watch.run(roots, server, creds, state, interval=args.interval)
            raise signin.SignedOut("the sign-in stopped working")  # run returns only then
    except signin.SignedOut as e:
        signin.save(auth_path, server, None)
        sys.exit(f"Signed out ({e}): run again to sign in.")
    except (watch.UploadFailed, signin.SignInError, signin.Unreachable) as e:
        sys.exit(str(e))
    except KeyboardInterrupt:
        pass


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(prog="altarmy-profit")
    p.add_argument(
        "--game-version",
        choices=list(versions.VERSIONS),
        default=versions.DEFAULT_VERSION,
        help="which game's data to use (default: %(default)s)",
    )
    p.add_argument(
        "--db", help="SQLite database file (default: DATABASE_URL, else data/altarmy-profit.sqlite)"
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("ingest", help="download DB2 tables from wago.tools and build the database")
    s.add_argument("--build", help='a build version, or "latest" (default: the pinned build)')
    s.add_argument("--cache", default="cache")
    s.add_argument(
        "--only-if-new", action="store_true", help="load the latest build, unless the database already has it"
    )
    s.set_defaults(fn=cmd_ingest)

    s = sub.add_parser("migrate", help="migrate the database to the newest schema revision")
    s.set_defaults(fn=cmd_migrate)

    s = sub.add_parser("prune", help=f"drop price observations older than {prices.KEEP_DAYS} days")
    s.set_defaults(fn=cmd_prune)

    s = sub.add_parser(
        "merge",
        help="recompute daily medians and the 7-day price statistics (every game version)",
    )
    s.set_defaults(fn=cmd_merge)

    s = sub.add_parser(
        "ahledger",
        help="record AHledger's newest auction house prices (every game version; AHLEDGER_API_KEY optional)",
    )
    s.set_defaults(fn=cmd_ahledger)

    s = sub.add_parser("serve", help="serve the API and the built front end (needs the [ui] extra)")
    s.add_argument("--host", default="127.0.0.1")
    s.add_argument("--port", type=int, default=8600)
    s.set_defaults(fn=cmd_serve)

    s = sub.add_parser(
        "watch", help="upload the addon files to an altarmy-profit server whenever WoW rewrites them"
    )
    s.add_argument("--server", required=True, help="e.g. https://alt-army.com")
    s.add_argument(
        "--sign-in",
        action="store_true",
        help="ask for the email and password even if a sign-in is saved (ALTARMY_EMAIL, ALTARMY_PASSWORD"
        " answer instead when set)",
    )
    s.add_argument("--create-account", action="store_true", help="create an account on the site, then watch")
    s.add_argument("--auth", default=str(signin.DEFAULT_AUTH), help="the saved sign-in (a refresh token)")
    s.add_argument("--interval", type=float, default=15, help="seconds between checks (default: 15)")
    s.add_argument("--once", action="store_true", help="upload what changed, then exit")
    s.add_argument("--state", default=str(watch.DEFAULT_STATE), help="which files were sent (JSON)")
    s.add_argument("--wow-root", action="append", help="a WoW install folder (repeatable)")
    s.set_defaults(fn=cmd_watch, needs_db=False)

    args = p.parse_args(argv)
    if not getattr(args, "needs_db", True):
        args.fn(args)
        return
    args.database = _database(args)
    try:
        args.fn(args)
    finally:
        args.database.dispose()


if __name__ == "__main__":
    main()
