"""Unit tests for scripts/build-recipe-server-facts.py. Run: python -m unittest scripts/test_build_recipe_server_facts.py"""
import importlib.util
import io
import json
import os
import tempfile
import unittest
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("build_recipe_server_facts",
                                               os.path.join(HERE, "build-recipe-server-facts.py"))
facts = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(facts)

CMANGOS_RELEASE = {"assets": [
    {"name": "tbc-mysql-db.zip", "updated_at": "2026-10-01T03:00:00Z", "browser_download_url": "https://x/mysql"},
    {"name": "tbc-sqlite-db.zip", "updated_at": "2026-10-01T04:00:00Z", "browser_download_url": "https://x/tbc"},
]}
VMANGOS_RELEASE = {"assets": [
    {"name": "db-mysql-abc1234.zip", "updated_at": "2026-10-01", "browser_download_url": "https://x/mysql"},
    {"name": "db-sqlite-abc1234.zip", "updated_at": "2026-10-01", "browser_download_url": "https://x/vm"},
]}


def zipped(member, data):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr(member, data)
    return buf.getvalue()


class LatestReleaseTest(unittest.TestCase):
    def test_cmangos_release_is_the_sqlite_assets_date(self):
        self.assertEqual(facts.latest_release("tbc", json.dumps(CMANGOS_RELEASE).encode()),
                         ("2026-10-01", "https://x/tbc"))

    def test_vmangos_release_is_the_sqlite_assets_name(self):
        self.assertEqual(facts.latest_release("forever", json.dumps(VMANGOS_RELEASE).encode()),
                         ("db-sqlite-abc1234", "https://x/vm"))

    def test_missing_asset_is_an_error(self):
        with self.assertRaises(SystemExit):
            facts.latest_release("tbc", json.dumps({"assets": []}).encode())


class StaleTest(unittest.TestCase):
    META = {"tbc": {"emulator": "cmangos", "release": "2026-09-24"},
            "forever": {"emulator": "vmangos", "release": "db-sqlite-4641790"}}

    def test_lists_versions_whose_release_moved(self):
        latest = {"tbc": "2026-10-01", "forever": "db-sqlite-4641790"}
        self.assertEqual(facts.stale(self.META, latest), [("tbc", "2026-09-24", "2026-10-01")])

    def test_current_meta_is_not_stale(self):
        latest = {"tbc": "2026-09-24", "forever": "db-sqlite-4641790"}
        self.assertEqual(facts.stale(self.META, latest), [])

    def test_a_version_never_recorded_is_stale(self):
        self.assertEqual(facts.stale({}, {"tbc": "2026-10-01"}), [("tbc", None, "2026-10-01")])

    def test_status_lines_give_staleness_and_each_latest_release(self):
        latest = {"tbc": "2026-10-01", "forever": "db-sqlite-4641790"}
        self.assertEqual(facts.status_lines(self.META, latest),
                         ["stale=true", "forever=db-sqlite-4641790", "tbc=2026-10-01"])

    def test_summary_names_each_moved_database(self):
        text = facts.summary([("tbc", "2026-09-24", "2026-10-01")])
        self.assertIn("cmangos", text)
        self.assertIn("`2026-09-24` → `2026-10-01`", text)


class DownloadTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fetched = []

    def tearDown(self):
        self.tmp.cleanup()

    def opener(self, payloads):
        def open_url(url):
            self.fetched.append(url)
            return io.BytesIO(payloads[url])
        return open_url

    def test_extracts_the_world_db_into_a_release_folder(self):
        opener = self.opener({
            facts.EMULATORS["forever"]["release_url"]: json.dumps(VMANGOS_RELEASE).encode(),
            "https://x/vm": zipped("db-sqlite-abc1234/mangos.sqlite", b"world"),
        })
        path = facts.download("forever", self.tmp.name, opener)
        self.assertEqual(path, os.path.join(self.tmp.name, "vmangos", "db-sqlite-abc1234", "mangos.sqlite"))
        with open(path, "rb") as f:
            self.assertEqual(f.read(), b"world")
        self.assertEqual(facts.release_id(path), "db-sqlite-abc1234")
        self.assertEqual(os.listdir(os.path.dirname(path)), ["mangos.sqlite"])  # archive removed

    def test_reuses_a_release_already_downloaded(self):
        opener = self.opener({
            facts.EMULATORS["tbc"]["release_url"]: json.dumps(CMANGOS_RELEASE).encode(),
            "https://x/tbc": zipped("tbcmangos.sqlite", b"tbc"),
        })
        facts.download("tbc", self.tmp.name, opener)
        facts.download("tbc", self.tmp.name, opener)
        self.assertEqual(self.fetched.count("https://x/tbc"), 1)


if __name__ == "__main__":
    unittest.main()
