"""Telegram integration contracts; no downloads or real systemd mutations."""
import importlib.util
import json
import hashlib
import io
import tarfile
from pathlib import Path
import subprocess
import socket
import tempfile
import unittest
from unittest import mock

from test_manager import zm, ROOT

spec = importlib.util.spec_from_file_location("telegram", ROOT + "/bin/telegram.py")
tg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tg)
tg.Fail, tg.sh, tg.http_get = zm.Fail, zm.sh, zm.http_get
tg.atomic_write, tg.SELF, tg.out = zm.atomic_write, zm.SELF, zm.out


class Telegram(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name) / "data"
        self.unit = Path(self.tmp.name) / "units" / tg.UNIT
        self.patchers = [mock.patch.object(tg, "BASE", self.base),
                         mock.patch.object(tg, "UNIT_PATH", self.unit)]
        for p in self.patchers:
            p.start()
            self.addCleanup(p.stop)

    def installed(self):
        revision = "a" * 40
        python = self.base / "engines" / revision / "venv/bin/python"
        python.parent.mkdir(parents=True)
        python.touch()
        tg.write_json("engine.json", {"revision": revision, "version": "test"})
        tg.config(create=True)

    def test_secret_stable_private_and_absent_from_status(self):
        first = tg.config(create=True)
        self.assertRegex(first["secret"], r"^[0-9a-f]{32}$")
        self.assertEqual(first, tg.config(create=True))
        self.assertEqual((self.base / "settings.json").stat().st_mode & 0o777, 0o600)
        self.assertNotIn(first["secret"], json.dumps(tg.state()))

    def test_invalid_settings_rejected(self):
        for port, secret in [(True, ""), (0, ""), (65536, ""), (1443, "--luaexec"), ("1443", "")]:
            with self.subTest(port=port, secret=secret):
                tg.write_json("settings.json", {"port": port, "secret": secret})
                with self.assertRaises(zm.Fail):
                    tg.config()

    def test_unit_only_user_process_and_escaped_path(self):
        with mock.patch.object(tg, "SELF", '/home/a %x/quote"/bin/manager'):
            unit = tg.unit_text()
        self.assertIn('a %%x/quote\\"', unit)
        self.assertIn('telegram run', unit)
        self.assertNotIn('sudo', unit)
        self.assertNotIn('secret', unit)

    def test_no_telegram_does_not_need_systemd(self):
        with mock.patch.object(tg, "sh") as run:
            self.assertFalse(tg.state()["installed"])
        run.assert_not_called()

    def test_missing_engine_cannot_be_started(self):
        with mock.patch.object(tg, "ctl") as ctl:
            with self.assertRaises(zm.Fail):
                tg.command(["on"])
        ctl.assert_not_called()

    def test_state_distinguishes_process_and_transport(self):
        self.installed()
        tg.write_json("check.json", {"results": [{"ok": False}]})
        r = subprocess.CompletedProcess([], 0, "ActiveState=active\nUnitFileState=enabled\n", "")
        with mock.patch.object(tg, "sh", return_value=r):
            state = tg.state()
        self.assertEqual(state["active"], "active")
        self.assertTrue(state["autostart"])
        self.assertFalse(state["check"]["results"][0]["ok"])

    def test_autostart_does_not_start_or_stop_service(self):
        self.installed()
        with mock.patch.object(tg, "ctl") as ctl:
            tg.command(["set", "autostart", "on"])
            ctl.assert_called_once_with("enable", tg.UNIT)

    def test_invalid_port_never_changes_config_or_service(self):
        self.installed()
        previous = tg.config()
        for port in ["1", "65536", "1443 --host 0.0.0.0", "abc", "-1443"]:
            with self.subTest(port=port), mock.patch.object(tg, "ctl") as ctl:
                with self.assertRaises(zm.Fail):
                    tg.command(["set", "port", port])
                ctl.assert_not_called()
                self.assertEqual(tg.config(), previous)

    def test_occupied_port_keeps_old_config(self):
        self.installed()
        previous = tg.config()
        with mock.patch.object(tg, "port_free", side_effect=zm.Fail("in use")):
            with self.assertRaises(zm.Fail):
                tg.command(["set", "port", "2443"])
        self.assertEqual(tg.config(), previous)

    def test_port_change_restores_config_after_restart_failure(self):
        self.installed()
        previous = tg.config()
        with mock.patch.object(tg, "port_free"), \
                mock.patch.object(tg, "state", return_value={"active": "active"}), \
                mock.patch.object(tg, "ctl") as ctl, \
                mock.patch.object(tg, "wait_ready", side_effect=zm.Fail("failed")):
            with self.assertRaises(zm.Fail):
                tg.command(["set", "port", "2443"])
        self.assertEqual(tg.config(), previous)
        self.assertEqual(ctl.call_count, 2)

    def test_link_remains_same_after_restart(self):
        self.installed()
        first = tg.command(["link"])
        with mock.patch.object(tg, "ctl"), mock.patch.object(tg, "wait_ready"):
            tg.command(["restart"])
        self.assertEqual(first, tg.command(["link"]))
        self.assertIn("server=127.0.0.1&port=1443&secret=dd", first["link"])

    def test_checksum_failure_does_not_replace_engine(self):
        self.installed()
        old = tg.read_json("engine.json", {})
        with mock.patch.object(tg, "http_get", return_value=b"corrupt"), mock.patch.object(tg, "out"):
            with self.assertRaisesRegex(zm.Fail, "checksum"):
                tg.install()
        self.assertEqual(tg.read_json("engine.json", {}), old)

    def test_log_redaction(self):
        secret = "a1" * 16
        text = 'Secret: ' + secret + '\ntg://proxy?server=127.0.0.1&secret=dd' + secret
        self.assertNotIn(secret, tg.redact(text))
        self.assertIn("[redacted]", tg.redact(text))

    def test_remove_disables_unit_and_preserves_connection(self):
        self.installed()
        self.unit.parent.mkdir()
        self.unit.write_text(tg.unit_text())
        previous = tg.config()
        with mock.patch.object(tg, "ctl") as ctl:
            tg.command(["remove"])
        ctl.assert_any_call("disable", "--now", tg.UNIT)
        self.assertFalse(self.unit.exists())
        self.assertIsNone(tg.engine())
        self.assertEqual(tg.config(), previous)

    def test_failed_stop_does_not_remove_running_engine(self):
        self.installed()
        self.unit.parent.mkdir()
        self.unit.write_text(tg.unit_text())
        with mock.patch.object(tg, "ctl", side_effect=zm.Fail("cannot stop")):
            with self.assertRaises(zm.Fail):
                tg.command(["remove"])
        self.assertIsNotNone(tg.engine())
        self.assertTrue(self.unit.exists())

    def test_invalid_revision_is_data_not_a_path(self):
        for value in ["../outside", [], None, "f" * 41]:
            with self.subTest(value=value):
                tg.write_json("engine.json", {"revision": value})
                self.assertIsNone(tg.engine())

    def test_archive_traversal_keeps_old_engine(self):
        self.installed()
        old = tg.read_json("engine.json", {})
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w:gz") as archive:
            member = tarfile.TarInfo("upstream/proxy/../../outside")
            member.size = 4
            archive.addfile(member, io.BytesIO(b"evil"))
        body = buf.getvalue()
        with mock.patch.object(tg, "http_get", return_value=body), \
                mock.patch.object(tg, "ARCHIVE_SHA", hashlib.sha256(body).hexdigest()), \
                mock.patch.object(tg, "state", return_value={"active": "inactive"}), \
                mock.patch.object(tg, "out"):
            with self.assertRaisesRegex(zm.Fail, "Unsafe"):
                tg.install()
        self.assertEqual(tg.read_json("engine.json", {}), old)
        self.assertFalse((self.base / "engines/outside").exists())

    def test_update_failure_restores_metadata_and_unit(self):
        self.installed()
        old = tg.read_json("engine.json", {})
        self.unit.parent.mkdir()
        self.unit.write_text("previous unit")
        body = b"already installed revision"
        with mock.patch.object(tg, "REVISION", old["revision"]), \
                mock.patch.object(tg, "http_get", return_value=body), \
                mock.patch.object(tg, "ARCHIVE_SHA", hashlib.sha256(body).hexdigest()), \
                mock.patch.object(tg, "state", return_value={"active": "active"}), \
                mock.patch.object(tg, "ctl"), \
                mock.patch.object(tg, "out"), \
                mock.patch.object(tg, "wait_ready", side_effect=zm.Fail("startup failed")):
            with self.assertRaisesRegex(zm.Fail, "startup"):
                tg.install()
        self.assertEqual(tg.read_json("engine.json", {}), old)
        self.assertEqual(self.unit.read_text(), "previous unit")

    def test_port_probe_allows_recently_closed_connections(self):
        with socket.socket() as listener:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
            listener.listen()
            with socket.create_connection(("127.0.0.1", port)) as client:
                connection, _ = listener.accept()
                # The server closes first, leaving its endpoint in TIME_WAIT.
                connection.close()
                self.assertEqual(client.recv(1), b"")
        tg.port_free(port)

    def test_port_probe_rejects_a_live_listener(self):
        with socket.socket() as listener:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            with self.assertRaisesRegex(zm.Fail, "already in use"):
                tg.port_free(listener.getsockname()[1])
