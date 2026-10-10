"""Manager tests: strategy validation, rendering, lists, blockcheck parsing.

    python3 -m unittest discover -s tests/manager
    OMARCHY_ZAPRET2_TEST_ENGINE=/path/to/zapret2-vX python3 -m unittest discover -s tests/manager

With the engine (an unpacked release) every bundled preset in every mode is
also checked by `nfqws2 --dry-run`.
"""

import importlib.machinery
import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
loader = importlib.machinery.SourceFileLoader("zm", os.path.join(ROOT, "bin", "omarchy-zapret2"))
spec = importlib.util.spec_from_loader("zm", loader)
zm = importlib.util.module_from_spec(spec)
loader.exec_module(zm)

ENGINE = os.environ.get("OMARCHY_ZAPRET2_TEST_ENGINE", "")


def preset_text(name):
    with open(os.path.join(zm.DATA, "presets", name + ".txt"), encoding="utf-8") as f:
        return f.read()


MINIMAL = """[TCP_HTTP]
--lua-desync=fake:blob=http_iana:tcp_md5
[TCP_TLS]
--lua-desync=fake:blob=tls_google:tcp_md5
[TCP_GENERIC]
--lua-desync=multisplit:pos=2
[QUIC]
--lua-desync=fake:blob=quic_google:repeats=6
"""


class Validation(unittest.TestCase):
    def test_every_bundled_preset_parses(self):
        for name in zm.PRESETS:
            with self.subTest(name=name):
                secs = zm.parse_preset(preset_text(name))
                for s in zm.REQUIRED:
                    self.assertTrue(secs[s])

    def test_minimal_ok(self):
        zm.parse_preset(MINIMAL)

    def rejects(self, extra, section="TCP_TLS"):
        text = MINIMAL.replace("[%s]\n" % section, "[%s]\n%s\n" % (section, extra), 1)
        with self.assertRaises(zm.Fail):
            zm.parse_preset(text)

    def test_rejects_code_and_files(self):
        self.rejects("--lua-desync=luaexec:code=os.execute")
        self.rejects("--lua-desync=condition:func=luaexec")
        self.rejects("--lua-init=@/tmp/x.lua")
        self.rejects("--lua-init=os.execute('id')")
        self.rejects("--blob=x:@/etc/shadow")
        self.rejects("--hostlist=/etc/shadow")
        self.rejects("--writable=/tmp")
        self.rejects("--user=root")
        self.rejects("--qnum=1")
        self.rejects("--debug=@/etc/passwd")
        self.rejects("--filter-udp=1-65535")                 # only voice may filter
        self.rejects("--lua-desync=fake:blob=unknown_blob")
        self.rejects("--lua-desync=fake:blob=tls_google:x=a/b")
        self.rejects("--lua-desync=fake:blob=tls_google:x=$(id)")
        self.rejects("--payload=evil")
        self.rejects("--out-range=../x")
        self.rejects("plain words")

    def test_structure(self):
        with self.assertRaises(zm.Fail):
            zm.parse_preset(MINIMAL.replace("[QUIC]\n--lua-desync=fake:blob=quic_google:repeats=6\n", ""))
        with self.assertRaises(zm.Fail):
            zm.parse_preset("--lua-desync=fake\n" + MINIMAL)
        with self.assertRaises(zm.Fail):
            zm.parse_preset(MINIMAL + "[BOGUS]\n")
        with self.assertRaises(zm.Fail):
            zm.parse_preset(MINIMAL + "[QUIC]\n--lua-desync=fake\n")
        with self.assertRaises(zm.Fail):
            zm.parse_preset(MINIMAL + "[IPSET_TCP_PORTS]\n99999\n")

    def test_voice_may_filter(self):
        zm.parse_preset(MINIMAL + "[VOICE_COMPATIBLE]\n--filter-udp=19294-19344,50000-50100\n--filter-l7=discord,stun\n"
                        "--payload=discord_ip_discovery\n--lua-desync=fake:blob=stun:repeats=3\n")

    def test_settings_are_untrusted(self):
        s = zm.clean_settings({"preset": "../../etc/x", "game": "rm -rf", "ipv6": "yes", "extra": 1})
        self.assertEqual(s, zm.DEFAULTS)
        s = zm.clean_settings({"preset": "my-own", "game": "all", "ipv6": False})
        self.assertEqual((s["preset"], s["game"], s["ipv6"]), ("my-own", "all", False))
        self.assertEqual(zm.clean_settings({"preset": "my-../x"})["preset"], zm.DEFAULTS["preset"])
        self.assertEqual(zm.clean_settings([1, 2]), zm.DEFAULTS)
        self.assertEqual(zm.DEFAULTS["lang"], "en")
        self.assertEqual(zm.clean_settings({"lang": "ru"})["lang"], "ru")
        self.assertEqual(zm.clean_settings({"lang": "de"})["lang"], "en")


class Lists(unittest.TestCase):
    def test_hosts(self):
        text = "YouTube.com\n*.googlevideo.com\n# c\nbad host\n../etc\nexample.org. # tail\nxn--d1acpjx3f.xn--p1ai\n^dns.google\n^^x\n"
        self.assertEqual(zm.clean_list(text, "host"),
                         ["youtube.com", "googlevideo.com", "example.org", "xn--d1acpjx3f.xn--p1ai", "^dns.google", "^x"])

    def test_ipsets(self):
        text = "1.2.3.0/24\n1.2.3.4/24\n2001:db8::/32\nnope\n300.1.1.1\n"
        self.assertEqual(zm.clean_list(text, "ipset"), ["1.2.3.0/24", "1.2.3.0/24", "2001:db8::/32"])

    def test_bundled_lists_are_clean(self):
        for name in zm.BASE_LISTS:
            with open(os.path.join(zm.DATA, "lists", name + ".txt"), encoding="utf-8") as f:
                lines = [l for l in f.read().splitlines() if l.strip()]
            self.assertEqual(len(zm.clean_list("\n".join(lines), zm.list_kind(name))), len(lines), name)

    def _save(self, var, text, *args):
        emitted = {}
        with mock.patch.object(zm, "require_installed", lambda: None), \
             mock.patch.object(zm, "VAR", var), \
             mock.patch.object(zm, "read_stdin", lambda cap: text), \
             mock.patch.object(zm, "restart_if_active", lambda: True), \
             mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
            zm.cmd_list(list(args))
        return emitted

    def test_save_restarts_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(os.path.join(var, "lists"))
            res = self._save(var, "example.com\n", "save", "list-general-user")
            self.assertTrue(res.get("ok"))
            self.assertTrue(res.get("restarted"))

    def test_save_no_restart_flag(self):
        restarted = []
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(os.path.join(var, "lists"))
            emitted = {}
            with mock.patch.object(zm, "require_installed", lambda: None), \
                 mock.patch.object(zm, "VAR", var), \
                 mock.patch.object(zm, "read_stdin", lambda cap: "example.com\n"), \
                 mock.patch.object(zm, "restart_if_active", lambda: restarted.append(True) or True), \
                 mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
                zm.cmd_list(["save", "list-general-user", "--no-restart"])
            self.assertTrue(emitted.get("ok"))
            self.assertFalse(emitted.get("restarted"))
            self.assertEqual(restarted, [])


class Rendering(unittest.TestCase):
    def test_merge_ports(self):
        self.assertEqual(zm.merge_ports(["443", "80", "1024-65535", "2053", "8443,443"]), ["80", "443", "1024-65535"])
        self.assertEqual(zm.merge_ports(["19294-19344", "443", "50000-50100"]), ["443", "19294-19344", "50000-50100"])

    def test_ports(self):
        secs = zm.parse_preset(preset_text("general"))
        tcp, udp = zm.ports_for(dict(zm.DEFAULTS), secs)
        self.assertEqual(tcp, ["80", "443", "2053", "2083", "2087", "2096", "8443"])
        self.assertEqual(udp, ["443", "1024-65535"])               # compatible voice without a preset block
        tcp, udp = zm.ports_for(dict(zm.DEFAULTS, voice="off"), secs)
        self.assertEqual(udp, ["443", "19294-19344", "50000-50100"])
        tcp, _ = zm.ports_for(dict(zm.DEFAULTS, game="tcp"), secs)
        self.assertEqual(tcp, ["80", "443", "1024-65535"])

    def render(self, name, settings, counts=None):
        counts = counts if counts is not None else {n: 1 for n in zm.BASE_LISTS}
        secs = zm.parse_preset(preset_text(name)) if name in zm.PRESETS else zm.parse_preset(MINIMAL)
        return zm.render_args(name, secs, settings, "/E", "/L", ["/F"], counts)

    def test_render_shape(self):
        args = self.render("general", dict(zm.DEFAULTS))
        self.assertEqual(args[0], "--qnum=%d" % zm.QNUM)
        self.assertIn("--user=nobody", args)
        self.assertNotIn("--new", args[-1:])
        self.assertFalse(any("{{" in a for a in args))
        self.assertFalse(any(a.startswith("--lua-init") and "/E/lua/" not in a for a in args))
        self.assertNotIn("--hostlist=/L/list-general-user.txt", args)         # empty user list left out
        self.assertIn("--ipset=/L/ipset-none.txt", args)                      # default: hostlists only
        self.assertNotIn("--ipset=/L/ipset-all.txt", args)
        self.assertIn("--ipset=/L/ipset-all.txt", self.render("general", dict(zm.DEFAULTS, ipset="loaded")))
        args = self.render("general", dict(zm.DEFAULTS), dict({n: 1 for n in zm.BASE_LISTS}, **{"list-general-user": 3}))
        self.assertIn("--hostlist=/L/list-general-user.txt", args)
        args = self.render("general", dict(zm.DEFAULTS, ipset="loaded"), {})
        self.assertIn("--ipset=/L/ipset-none.txt", args)                      # loaded but empty
        args = self.render("general", dict(zm.DEFAULTS, ipset="any"))
        self.assertFalse(any(a.startswith("--ipset=") for a in args))

    def test_custom_presets_get_discord_web(self):
        self.assertIn("--hostlist=/L/list-discord-web.txt", self.render("custom-safe", dict(zm.DEFAULTS)))
        self.assertNotIn("--hostlist=/L/list-discord-web.txt", self.render("general", dict(zm.DEFAULTS)))

    def test_game(self):
        self.assertIn("--filter-tcp=12", self.render("general", dict(zm.DEFAULTS)))
        a = self.render("general", dict(zm.DEFAULTS, game="all"))
        self.assertIn("--filter-tcp=1024-65535", a)
        self.assertIn("--filter-udp=1024-65535", a)

    def test_nft(self):
        text = zm.render_nft(["80", "443"], ["443"], ipv6=False)
        self.assertIn("table inet omarchy_zapret2 {", text)
        self.assertIn("queue num 220 bypass", text)
        self.assertIn("meta nfproto ipv6 return", text)
        self.assertIn("meta oiftype 65534 return", text)        # tunnels untouched
        self.assertIn("meta iiftype 65534 return", text)
        self.assertIn("tcp dport { 80, 443 }", text)
        self.assertNotIn("nfproto ipv6", zm.render_nft(["80"], ["443"]))

    @unittest.skipUnless(shutil.which("unshare") and shutil.which("nft"), "needs unshare and nft")
    def test_nft_applies_in_a_namespace(self):
        for tcp, udp, v6 in ((["80", "443"], ["443", "1024-65535"], True),
                             (zm.merge_ports(["80", "443", "1024-65535"]), ["443", "19294-19344"], False)):
            with tempfile.NamedTemporaryFile("w", suffix=".nft") as f:
                f.write(zm.render_nft(tcp, udp, v6))
                f.flush()
                r = subprocess.run(["unshare", "-rn", "nft", "-f", f.name], capture_output=True, text=True, timeout=20)
                if r.returncode != 0 and "Operation not permitted" in r.stderr:
                    self.skipTest("user namespaces are not available")
                self.assertEqual(r.returncode, 0, r.stderr)

    @unittest.skipUnless(ENGINE, "set OMARCHY_ZAPRET2_TEST_ENGINE to an unpacked zapret2 release")
    def test_dry_run_every_preset(self):
        nfqws = os.path.join(ENGINE, "binaries", "linux-x86_64", "nfqws2")
        with tempfile.TemporaryDirectory() as lists:
            counts = {}
            for n in zm.BASE_LISTS + zm.USER_LISTS + ("ipset-none",):
                kind = zm.list_kind(n)
                with open(os.path.join(lists, n + ".txt"), "w") as f:
                    f.write("1.2.3.0/24\n" if kind == "ipset" else "example.com\n")
                counts[n] = 1
            fakes = [os.path.join(ENGINE, "files", "fake"), os.path.join(zm.DATA, "fake")]
            modes = [dict(zm.DEFAULTS), dict(zm.DEFAULTS, game="all", ipset="any", voice="standard"),
                     dict(zm.DEFAULTS, voice="off", ipset="none")]
            for name in zm.PRESETS:
                secs = zm.parse_preset(preset_text(name))
                for s in modes:
                    with self.subTest(name=name, settings=s):
                        args = zm.render_args(name, secs, s, ENGINE, lists, fakes, counts)
                        args = [a for a in args if a != "--user=nobody"]
                        r = subprocess.run([nfqws, "--dry-run"] + args, capture_output=True, text=True, timeout=20)
                        self.assertEqual(r.returncode, 0, r.stdout[-600:] + r.stderr[-600:])


class Blockcheck(unittest.TestCase):
    LOG = """* SUMMARY
!!!!! curl_test_https_tls12: working strategy found for ipv4 youtube.com : nfqws2 --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5 --lua-desync=multisplit:pos=1 !!!!!
!!!!! curl_test_http3: working strategy found for ipv4 youtube.com : nfqws2 --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6 !!!!!
!!!!! curl_test_http: working strategy found for ipv4 example.com : nfqws2 --lua-init=@/tmp/x.lua --lua-desync=luaexec:code=1 !!!!!
"""

    def test_parse(self):
        found = zm.parse_blockcheck(self.LOG)
        self.assertEqual([f["test"] for f in found], ["curl_test_https_tls12", "curl_test_http3", "curl_test_http"])
        self.assertEqual(found[0]["domain"], "youtube.com")

    def test_to_strategy(self):
        found = zm.parse_blockcheck(self.LOG)
        secs = zm.parse_preset(zm.strategy_from_found(found[0]))
        self.assertIn("--lua-desync=multisplit:pos=1", secs["TCP_TLS"])
        secs = zm.parse_preset(zm.strategy_from_found(found[1]))
        self.assertIn("--lua-desync=fake:blob=fake_default_quic:repeats=6", secs["QUIC"])
        with self.assertRaises(zm.Fail):
            zm.strategy_from_found(found[2])


class Flowseal(unittest.TestCase):
    def test_every_flowseal_preset_parses(self):
        d = os.path.join(zm.DATA, "presets", "flowseal")
        files = sorted(f for f in os.listdir(d) if f.endswith(".txt"))
        self.assertTrue(files)
        for f in files:
            with self.subTest(name=f):
                with open(os.path.join(d, f), encoding="utf-8") as fh:
                    secs = zm.parse_full(fh.read())
                self.assertTrue(secs["full"])

    SAMPLE_BAT = (
        "@echo off\r\n"
        "set LISTS=lists\r\n"
        "set BIN=bin\\\r\n"
        '"C:\\zapret\\winws.exe" ^\r\n'
        "--wf-tcp=80,443 ^\r\n"
        "--wf-udp=443 ^\r\n"
        "--filter-tcp=80,443 ^\r\n"
        "--hostlist=%LISTS%list-general.txt ^\r\n"
        "--dpi-desync=fake,multisplit ^\r\n"
        "--dpi-desync-fooling=ts ^\r\n"
        "--dpi-desync-cutoff=n3 ^\r\n"
        "--dpi-desync-fake-tls=%BIN%tls_clienthello_www_google_com.bin ^\r\n"
        "--dpi-desync-split-pos=1 ^\r\n"
        "--new ^\r\n"
        "--filter-tcp=%GameFilterTCP% ^\r\n"
        "--dpi-desync=fake\r\n"
    )

    def test_translate_bat_sample(self):
        text = zm.translate_bat(self.SAMPLE_BAT, "general.bat")
        self.assertIn("@tcp=80,443", text)
        self.assertIn("@udp=443", text)
        self.assertIn("--hostlist={{LISTS}}/list-general.txt", text)
        self.assertIn("--out-range=-n2", text)
        self.assertIn("blob=fs_tls_clienthello_www_google_com", text)
        self.assertIn("tcp_ts=-1000", text)
        self.assertIn("--lua-desync=multisplit:", text)
        self.assertIn("--lua-desync=fake:", text)
        self.assertIn("--filter-tcp={{GAME_TCP}}", text)
        zm.parse_full(text)

    def test_check_desync_func_params(self):
        with self.assertRaises(zm.Fail):
            zm.check_desync("fake:fool=x")
        with self.assertRaises(zm.Fail):
            zm.check_desync("fake:ipfrag=evil")
        zm.check_desync("fake:ipfrag=ipfrag2")

    def test_render_full_ipset_modes(self):
        lines = ["@tcp=80,443", "@udp=443", "--filter-tcp=80,443",
                 "--ipset={{LISTS}}/ipset-all.txt", "--payload=known", "--lua-desync=multisplit:pos=1"]
        args, _ = zm.render_full(lines, dict(zm.DEFAULTS, ipset="none"), "/E", "/L", {})
        self.assertIn("--ipset=/L/ipset-none.txt", args)
        self.assertNotIn("--ipset=/L/ipset-all.txt", args)
        args, _ = zm.render_full(lines, dict(zm.DEFAULTS, ipset="loaded"), "/E", "/L",
                                 {"ipset-all": 5})
        self.assertIn("--ipset=/L/ipset-all.txt", args)
        args, _ = zm.render_full(lines, dict(zm.DEFAULTS, ipset="loaded"), "/E", "/L", {})
        self.assertIn("--ipset=/L/ipset-none.txt", args)
        args, _ = zm.render_full(lines, dict(zm.DEFAULTS, ipset="any"), "/E", "/L", {"ipset-all": 5})
        self.assertFalse(any(a.startswith("--ipset=") for a in args))


class NewFeatures(unittest.TestCase):
    def test_game_port_validation(self):
        self.assertEqual(zm.clean_settings({"gameTcp": "8080,9000-9010"})["gameTcp"], "8080,9000-9010")
        self.assertEqual(zm.clean_settings({"gameUdp": "443"})["gameUdp"], "443")
        for bad in ("0", "99999", "80-", "abc", "80,,443", "", "1-2-3",
                    ",".join(str(1000 + i) for i in range(17)), 123, None):
            with self.subTest(value=bad):
                key = "gameTcp"
                self.assertEqual(zm.clean_settings({key: bad})[key], zm.DEFAULTS[key])
        s = zm.clean_settings({"gameTcp": "7000-7100", "gameUdp": "8000"})
        self.assertEqual((s["gameTcp"], s["gameUdp"]), ("7000-7100", "8000"))

    def test_game_custom_ports_render(self):
        lines = ["@tcp=80,443,{{GAME_TCP}}", "@udp=443,{{GAME_UDP}}",
                 "--filter-tcp={{GAME_TCP}}", "--filter-udp={{GAME_UDP}}",
                 "--payload=known", "--lua-desync=multisplit:pos=1"]
        s = dict(zm.DEFAULTS, game="all", gameTcp="7000-7100", gameUdp="8000-8010")
        args, (tcp, udp) = zm.render_full(lines, s, "/E", "/L", {})
        self.assertIn("--filter-tcp=7000-7100", args)
        self.assertIn("--filter-udp=8000-8010", args)
        self.assertIn("7000-7100", tcp)
        self.assertIn("8000-8010", udp)
        s = dict(zm.DEFAULTS, game="off", gameTcp="7000-7100", gameUdp="8000-8010")
        args, _ = zm.render_full(lines, s, "/E", "/L", {})
        self.assertIn("--filter-tcp=12", args)
        self.assertIn("--filter-udp=12", args)
        self.assertNotIn("--filter-tcp=7000-7100", args)

    def test_fake_validation_and_substitution(self):
        choices = zm.fake_choices()
        self.assertTrue(choices)
        self.assertTrue(all(c.startswith("fs_quic_") or c.startswith("fs_stun") for c in choices))
        self.assertEqual(zm.clean_settings({"discordFake": choices[0]})["discordFake"], choices[0])
        self.assertEqual(zm.clean_settings({"discordFake": "nope"})["discordFake"], "default")
        self.assertEqual(zm.clean_settings({"gameFake": "fs_tls_clienthello_www_google_com"})["gameFake"], "default")
        lines = ["@tcp=80,443", "@udp=443",
                 "--lua-desync=fake:blob=fs_active_discord_udp:repeats=6",
                 "--lua-desync=fake:blob=fs_active_game_udp:repeats=12"]
        args, _ = zm.render_full(lines, dict(zm.DEFAULTS), "/E", "/L", {})
        self.assertIn("--lua-desync=fake:blob=fs_active_discord_udp:repeats=6", args)
        d, g = choices[0], choices[-1]
        args, _ = zm.render_full(lines, dict(zm.DEFAULTS, discordFake=d, gameFake=g), "/E", "/L", {})
        self.assertIn("--lua-desync=fake:blob=%s:repeats=6" % d, args)
        self.assertIn("--lua-desync=fake:blob=%s:repeats=12" % g, args)
        self.assertFalse(any("fs_active_discord_udp" in a or "fs_active_game_udp" in a
                             for a in args if a.startswith("--lua-desync=")))

    def test_clean_hosts(self):
        text = ("127.0.0.1 localhost\n0.0.0.0 example.com ads.example.org # tail\n"
                "::1 ipv6.example.com\nnot-an-ip example.com\n1.2.3.4 bad_host!\n"
                "# comment\n\n1.2.3.4 single\n")
        self.assertEqual(zm.clean_hosts(text),
                         ["127.0.0.1 localhost", "0.0.0.0 example.com ads.example.org",
                          "::1 ipv6.example.com", "1.2.3.4 single"])

    def test_apply_hosts_block(self):
        original = "127.0.0.1 localhost\n8.8.8.8 dns\n"
        with_block = zm.apply_hosts_block(original, ["0.0.0.0 a.com", "0.0.0.0 b.com"])
        self.assertIn("127.0.0.1 localhost", with_block)
        self.assertIn("8.8.8.8 dns", with_block)
        self.assertIn(zm.HOSTS_BEGIN, with_block)
        self.assertIn(zm.HOSTS_END, with_block)
        self.assertIn("0.0.0.0 a.com", with_block)
        again = zm.apply_hosts_block(with_block, ["0.0.0.0 a.com", "0.0.0.0 b.com"])
        self.assertEqual(again, with_block)                       # idempotent
        replaced = zm.apply_hosts_block(with_block, ["0.0.0.0 c.com"])
        self.assertIn("0.0.0.0 c.com", replaced)
        self.assertNotIn("0.0.0.0 a.com", replaced)
        self.assertEqual(replaced.count(zm.HOSTS_BEGIN), 1)
        removed = zm.apply_hosts_block(replaced, None)
        self.assertEqual(removed, original)
        self.assertEqual(zm.apply_hosts_block(removed, None), original)


class ExportImport(unittest.TestCase):
    def _setup_var(self, tmp):
        import json
        var = os.path.join(tmp, "var")
        os.makedirs(os.path.join(var, "lists"))
        os.makedirs(os.path.join(var, "custom"))
        with open(os.path.join(var, "settings.json"), "w", encoding="utf-8") as f:
            json.dump({"preset": "my-own", "game": "all"}, f)
        with open(os.path.join(var, "lists", "list-general-user.txt"), "w", encoding="utf-8") as f:
            f.write("example.com\n")
        with open(os.path.join(var, "custom", "my-own.txt"), "w", encoding="utf-8") as f:
            f.write(MINIMAL)
        return var

    def _export_stdout(self, var):
        emitted = {}
        with mock.patch.object(zm, "VAR", var), \
             mock.patch.object(zm, "require_installed", lambda: None), \
             mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
            zm.cmd_export(["--stdout"])
        return emitted

    def _import_stdin(self, var, text):
        emitted = {}
        with mock.patch.object(zm, "require_installed", lambda: None), \
             mock.patch.object(zm, "VAR", var), \
             mock.patch.object(zm, "read_stdin", lambda cap: text), \
             mock.patch.object(zm, "restart_if_active", lambda: True), \
             mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
            zm.cmd_import([])
        return emitted

    def _zip_b64(self, members):
        import base64
        import io
        import zipfile
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            for name, content in members.items():
                zf.writestr(name, content)
        return base64.b64encode(buf.getvalue()).decode("ascii")

    def test_roundtrip(self):
        import base64
        import io
        import json as _json
        import zipfile
        with tempfile.TemporaryDirectory() as tmp:
            var = self._setup_var(tmp)
            res = self._export_stdout(var)
            self.assertTrue(res.get("ok"))
            self.assertIn("settings.json", res.get("files", []))
            names = zipfile.ZipFile(io.BytesIO(base64.b64decode(res["data"]))).namelist()
            self.assertIn("settings.json", names)
            self.assertIn("lists/list-general-user.txt", names)
            self.assertIn("custom/my-own.txt", names)
            # restore into a fresh VAR
            var2 = os.path.join(tmp, "var2")
            os.makedirs(os.path.join(var2, "lists"))
            os.makedirs(os.path.join(var2, "custom"))
            res2 = self._import_stdin(var2, res["data"])
            self.assertTrue(res2.get("ok"))
            with open(os.path.join(var2, "settings.json"), encoding="utf-8") as f:
                s = _json.load(f)
            self.assertEqual(s["preset"], "my-own")
            with open(os.path.join(var2, "lists", "list-general-user.txt"), encoding="utf-8") as f:
                self.assertIn("example.com", f.read())
            with open(os.path.join(var2, "custom", "my-own.txt"), encoding="utf-8") as f:
                zm.parse_preset(f.read())

    def test_reject_oversize(self):
        import json as _json
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(os.path.join(var, "lists"))
            os.makedirs(os.path.join(var, "custom"))
            data = self._zip_b64({"settings.json": _json.dumps({"preset": "my-x"}),
                                  "lists/list-general-user.txt": "a.com\n" * (100 * 1024)})
            with self.assertRaises(zm.Fail):
                self._import_stdin(var, data)

    def test_reject_bad_preset(self):
        import json as _json
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(os.path.join(var, "lists"))
            os.makedirs(os.path.join(var, "custom"))
            evil = MINIMAL.replace("[TCP_TLS]\n", "[TCP_TLS]\n--lua-desync=luaexec:code=1\n", 1)
            data = self._zip_b64({"settings.json": _json.dumps({"preset": "my-evil"}),
                                  "custom/my-evil.txt": evil})
            with self.assertRaises(zm.Fail):
                self._import_stdin(var, data)
            self.assertFalse(os.path.exists(os.path.join(var, "custom", "my-evil.txt")))

    def test_reject_zip_slip_and_unknown(self):
        import json as _json
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(os.path.join(var, "lists"))
            os.makedirs(os.path.join(var, "custom"))
            settings = _json.dumps({"preset": "my-x"})
            for evil in ("../evil.txt", "/abs.txt", "custom/../../x.txt",
                         "lists/list-general.txt", "flowseal/fs-general.txt", "other.txt"):
                with self.subTest(name=evil):
                    data = self._zip_b64({"settings.json": settings, evil: "example.com\n"})
                    with self.assertRaises(zm.Fail):
                        self._import_stdin(var, data)


class PresetsShow(unittest.TestCase):
    def _show(self, *args):
        emitted = {}
        with mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
            zm.cmd_presets_show(list(args))
        return emitted

    def test_next(self):
        res = self._show("general")
        self.assertTrue(res.get("ok"))
        self.assertEqual(res.get("name"), "general")
        self.assertIn("[TCP_TLS]", res.get("text", ""))

    def test_fs_bundled(self):
        d = os.path.join(zm.DATA, "presets", "flowseal")
        name = sorted(f[:-4] for f in os.listdir(d) if f.endswith(".txt"))[0]
        self.assertTrue(name.startswith("fs-"))
        res = self._show(name)
        self.assertTrue(res.get("ok"))
        self.assertEqual(res.get("name"), name)
        self.assertTrue(res.get("text"))

    def test_fs_var_override(self):
        d = os.path.join(zm.DATA, "presets", "flowseal")
        name = sorted(f[:-4] for f in os.listdir(d) if f.endswith(".txt"))[0]
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(os.path.join(var, "flowseal"))
            with open(os.path.join(var, "flowseal", name + ".txt"), "w", encoding="utf-8") as f:
                f.write("# override\n@tcp=80,443\n@udp=443\n--payload=known\n--lua-desync=multisplit:pos=1\n")
            with mock.patch.object(zm, "VAR", var):
                res = self._show(name)
        self.assertTrue(res.get("ok"))
        self.assertEqual(res.get("name"), name)
        self.assertIn("# override", res.get("text", ""))

    def test_my(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(os.path.join(var, "custom"))
            with open(os.path.join(var, "custom", "my-foo.txt"), "w", encoding="utf-8") as f:
                f.write(MINIMAL)
            with mock.patch.object(zm, "VAR", var):
                res = self._show("my-foo")
                self.assertTrue(res.get("ok"))
                self.assertEqual(res.get("name"), "my-foo")
                self.assertIn("[TCP_TLS]", res.get("text", ""))
                res = self._show("foo")                     # short name resolves to my-foo
                self.assertEqual(res.get("name"), "my-foo")

    def test_not_found(self):
        with self.assertRaises(zm.Fail):
            self._show("no-such-xyz")
        with self.assertRaises(zm.Fail):
            self._show("fs-no-such-xyz")
        with self.assertRaises(zm.Fail):
            self._show("my-no-such-xyz")
        with self.assertRaises(zm.Fail):
            self._show()


class AutopickServiceState(unittest.TestCase):
    def _run(self, baseline_score, preset_scores):
        """Run cmd_autopick with stubbed side effects; return (calls, result)."""
        calls = []
        saved = {}
        emitted = {}
        names = ["p%d" % i for i in range(len(preset_scores))]
        scores = list(preset_scores)
        state = {"n": 0}

        def fake_run_checks():
            seq = [baseline_score] + scores
            score = seq[min(state["n"], len(seq) - 1)]
            state["n"] += 1
            return {"time": 0, "score": score, "total": 10,
                    "categories": {"web": {"ok": score, "total": 10,
                                           "label": "w", "results": []}}}

        settings = {"preset": names[0], "ipv6": False}
        with mock.patch.object(zm, "require_installed", lambda: None), \
             mock.patch.object(zm, "unit_state", lambda u: {"ActiveState": "inactive"}), \
             mock.patch.object(zm, "all_presets",
                               lambda: [{"name": n, "group": "g"} for n in names]), \
             mock.patch.object(zm, "custom_names", lambda: []), \
             mock.patch.object(zm, "load_settings", lambda: dict(settings)), \
             mock.patch.object(zm, "save_settings", lambda s: settings.update(s)), \
             mock.patch.object(zm, "progress", lambda **kw: None), \
             mock.patch.object(zm, "systemctl",
                               lambda verb, unit: calls.append((verb, unit))), \
             mock.patch.object(zm, "run_checks", fake_run_checks), \
             mock.patch.object(zm, "wait_active", lambda timeout=8.0: None), \
             mock.patch.object(zm, "save_state",
                               lambda name, obj: saved.update({name: obj})), \
             mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
            zm.cmd_autopick([",".join(names)])
        return calls, saved["autopick.json"], emitted

    def test_not_needed_stops_service(self):
        calls, result, _ = self._run(8, [3, 4])
        self.assertTrue(result["notNeeded"])
        self.assertEqual(calls[-1], ("stop", zm.UNIT))

    def test_needed_keeps_service_on(self):
        calls, result, _ = self._run(2, [3, 8])
        self.assertFalse(result["notNeeded"])
        self.assertEqual(calls[-1], ("restart", zm.UNIT))
        self.assertNotEqual(calls[-1], ("stop", zm.UNIT))


class CircularPlanner(unittest.TestCase):
    def test_ranks_and_fills_from_other_domains(self):
        names = {"a", "b", "c"}
        scores = {"one": {"a": {"ok": 2, "total": 2}, "b": {"ok": 0, "total": 2}},
                  "two": {"b": {"ok": 2, "total": 2}, "c": {"ok": 1, "total": 2}}}
        result = zm.circular_rank(scores, 2, names)
        self.assertEqual(result["one"], ["a", "b"])
        self.assertEqual(result["two"], ["b", "c"])

    def test_config_only_contains_valid_names(self):
        result = zm.circular_config({"one": {"good": {"ok": 1, "total": 1}, "bad": {"ok": 0, "total": 1}}}, [], "quick", {"good"})
        self.assertEqual(result["domains"]["one"], ["good"])
        self.assertEqual(result["next"], "ready")

    def test_saved_findings_reference_existing_files(self):
        findings = [{"test": "curl_test_tls", "ip": "ipv4", "domain": "YouTube.com",
                     "args": "--lua-desync=fake:blob=tls_google:tcp_md5:repeats=6 --lua-desync=multisplit:pos=2,midsld"}]
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(zm, "var_path", side_effect=lambda *p: os.path.join(tmp, *p)):
                by_domain = zm.save_circular_findings(findings)
            names = by_domain["youtube.com"]
            self.assertEqual(len(names), 1)
            self.assertFalse(names[0].startswith("my-my-"), names[0])
            self.assertTrue(os.path.isfile(os.path.join(tmp, "custom", names[0] + ".txt")))



    def test_fails(self):
        a = {"preset": "a", "score": 8, "total": 14,
             "categories": {"youtube": [0, 6], "discord": [4, 4], "google": [2, 2], "cloudflare": [2, 2]}}
        b = {"preset": "b", "score": 12, "total": 14,
             "categories": {"youtube": [5, 6], "discord": [3, 4], "google": [2, 2], "cloudflare": [2, 2]}}
        self.assertEqual(zm.autopick_fails(a), 1)
        self.assertEqual(zm.autopick_fails(b), 2)
        self.assertTrue(zm.autopick_better(a, b))
        self.assertFalse(zm.autopick_better(b, a))

    def test_untested_never_beats_tested(self):
        tested = {"preset": "t", "score": 1, "total": 10, "categories": {"web": [1, 10]}}
        untested = {"preset": "u", "score": 0, "total": 0, "categories": {}}
        self.assertTrue(zm.autopick_better(tested, untested))
        self.assertFalse(zm.autopick_better(untested, tested))

    def test_full_pass_beats_quic_fail(self):
        full = {"preset": "full", "score": 14, "total": 14,
                "categories": {"youtube": [6, 6], "discord": [4, 4], "google": [2, 2], "cloudflare": [2, 2]}}
        quic = {"preset": "quic", "score": 12, "total": 14,
                "categories": {"youtube": [4, 6], "discord": [4, 4], "google": [2, 2], "cloudflare": [2, 2]}}
        self.assertTrue(zm.autopick_better(full, quic))


class CustomFullPresets(unittest.TestCase):
    FULL_MINIMAL = ("@tcp=80,443\n@udp=443\n--filter-tcp=80,443\n"
                    "--payload=known\n--lua-desync=multisplit:pos=1\n")
    FULL_FILTER_ONLY = ("--filter-tcp=80,443\n--payload=known\n"
                        "--lua-desync=multisplit:pos=1\n")

    def test_detect_full_vs_simple(self):
        self.assertFalse(zm.is_full_preset_text(MINIMAL))
        voice = (MINIMAL + "[VOICE_COMPATIBLE]\n--filter-udp=19294-19344\n"
                 "--filter-l7=discord,stun\n--payload=discord_ip_discovery\n"
                 "--lua-desync=fake:blob=stun:repeats=3\n")
        self.assertFalse(zm.is_full_preset_text(voice))   # simple stays simple
        self.assertTrue(zm.is_full_preset_text(self.FULL_MINIMAL))
        self.assertTrue(zm.is_full_preset_text(self.FULL_FILTER_ONLY))

    def _save(self, var, stdin_text, *args):
        emitted = {}
        with mock.patch.object(zm, "require_installed", lambda: None), \
             mock.patch.object(zm, "VAR", var), \
             mock.patch.object(zm, "read_stdin", lambda cap: stdin_text), \
             mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
            zm.cmd_custom(list(args))
        return emitted

    def test_save_full_format_custom_preset(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(os.path.join(var, "custom"))
            res = self._save(var, self.FULL_MINIMAL, "save", "fulltest")
            self.assertTrue(res.get("ok"))
            self.assertEqual(res.get("name"), "my-fulltest")
            path = os.path.join(var, "custom", "my-fulltest.txt")
            with open(path, encoding="utf-8") as f:
                stored = f.read()
            self.assertIn("@tcp=", stored)
            zm.parse_full(stored)                          # stored validates as full
            shown = {}
            with mock.patch.object(zm, "require_installed", lambda: None), \
                 mock.patch.object(zm, "VAR", var), \
                 mock.patch.object(zm, "out", lambda obj: shown.update(obj)):
                zm.cmd_custom(["show", "my-fulltest"])
            self.assertIn("@tcp=", shown.get("text", ""))

    def test_save_full_rejects_bad_desync(self):
        bad = "@tcp=80,443\n@udp=443\n--filter-tcp=80,443\n--payload=known\n--lua-desync=luaexec:code=1\n"
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(os.path.join(var, "custom"))
            with self.assertRaises(zm.Fail):
                self._save(var, bad, "save", "badfull")
            self.assertFalse(os.path.exists(os.path.join(var, "custom", "my-badfull.txt")))

    def test_save_simple_still_works(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(os.path.join(var, "custom"))
            res = self._save(var, MINIMAL, "save", "my-simple")
            self.assertEqual(res.get("name"), "my-simple")
            with open(os.path.join(var, "custom", "my-simple.txt"), encoding="utf-8") as f:
                zm.parse_preset(f.read())

    def test_load_full_custom_preset_for_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(os.path.join(var, "custom"))
            with open(os.path.join(var, "custom", "my-fullrun.txt"), "w", encoding="utf-8") as f:
                f.write(self.FULL_MINIMAL)
            with mock.patch.object(zm, "VAR", var):
                secs = zm.load_preset_for_run("my-fullrun", os.getuid())
            self.assertIn("full", secs)
            self.assertTrue(any(l.startswith("--lua-desync=") for l in secs["full"]))
            args, (tcp, udp) = zm.render_full(secs["full"], dict(zm.DEFAULTS), "/E", "/L", {})
            self.assertIn("--lua-desync=multisplit:pos=1", args)
            self.assertIn("80", tcp)
            self.assertIn("443", udp)

    def test_load_simple_custom_preset_for_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(os.path.join(var, "custom"))
            with open(os.path.join(var, "custom", "my-simplerun.txt"), "w", encoding="utf-8") as f:
                f.write(MINIMAL)
            with mock.patch.object(zm, "VAR", var):
                secs = zm.load_preset_for_run("my-simplerun", os.getuid())
            self.assertNotIn("full", secs)
            for s in zm.REQUIRED:
                self.assertTrue(secs[s])


class CheckDomains(unittest.TestCase):
    def _check(self, args, probe_ok=True):
        emitted = {}
        saved = {}

        def fake_probe(url, http3=False, timeout=6):
            return {"url": url, "ok": probe_ok, "code": "200" if probe_ok else "000",
                    "time": 0.1 if probe_ok else None, "error": "" if probe_ok else "timed out"}

        with mock.patch.object(zm, "curl_probe", fake_probe), \
             mock.patch.object(zm, "installed", lambda: False), \
             mock.patch.object(zm, "save_state", lambda name, obj: saved.update({name: obj})), \
             mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
            zm.cmd_check(list(args))
        return emitted, saved.get("check.json", {})

    def test_single_domain_ok(self):
        emitted, saved = self._check(["Example.COM "])
        self.assertTrue(emitted.get("ok"))
        self.assertEqual(emitted.get("domains"), ["example.com"])
        self.assertEqual(saved.get("domains"), ["example.com"])
        cat = emitted["categories"]["domain"]
        self.assertEqual((cat["ok"], cat["total"]), (1, 1))
        self.assertEqual(cat["results"][0]["url"], "https://example.com")
        self.assertNotIn("youtube", emitted["categories"])

    def test_dedupes(self):
        emitted, _ = self._check(["a.com", "A.COM", "a.com"])
        self.assertEqual(emitted.get("domains"), ["a.com"])
        self.assertEqual(emitted["categories"]["domain"]["total"], 1)

    def test_invalid_rejected(self):
        for bad in ("bad_host!", "https://x.com", "a/b", "x:8080", "", "  "):
            with self.subTest(domain=bad):
                with self.assertRaises(zm.Fail):
                    self._check([bad])

    def test_too_many_rejected(self):
        with self.assertRaises(zm.Fail):
            self._check(["d%d.example.com" % i for i in range(11)])

    def test_no_args_as_before(self):
        emitted = {}
        canned = {"time": 0, "score": 3, "total": 3, "categories": {"web": {"label": "w", "ok": 3, "total": 3}}}
        with mock.patch.object(zm, "run_checks", lambda: dict(canned)), \
             mock.patch.object(zm, "installed", lambda: False), \
             mock.patch.object(zm, "save_state", lambda name, obj: None), \
             mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
            zm.cmd_check([])
        self.assertTrue(emitted.get("ok"))
        self.assertNotIn("domains", emitted)
        self.assertEqual(emitted["categories"], canned["categories"])


class UpdateCheck(unittest.TestCase):
    def _set(self, var, key, value, calls):
        emitted = {}
        with mock.patch.object(zm, "require_installed", lambda: None), \
             mock.patch.object(zm, "VAR", var), \
             mock.patch.object(zm, "restart_if_active", lambda: calls.append(1) or True), \
             mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
            zm.cmd_set(key, value)
        return emitted

    def test_on_off(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(var)
            for key in ("update_check", "updatecheck"):
                calls = []
                res = self._set(var, key, "on", calls)
                self.assertTrue(res.get("ok"))
                self.assertTrue(res["settings"]["updateCheck"])
                self.assertFalse(res.get("restarted"))
                self.assertEqual(calls, [])                  # no service restart for a UI-only flag
                calls = []
                res = self._set(var, key, "off", calls)
                self.assertTrue(res.get("ok"))
                self.assertFalse(res["settings"]["updateCheck"])
                self.assertFalse(res.get("restarted"))
                self.assertEqual(calls, [])

    def test_invalid_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = os.path.join(tmp, "var")
            os.makedirs(var)
            with self.assertRaises(zm.Fail):
                self._set(var, "update_check", "maybe", [])

    def test_status_has_updates(self):
        emitted = {}
        cached = {"time": 111, "engine": True, "lists": False, "presets": None, "latest": "v9"}
        with mock.patch.object(zm, "installed", lambda: False), \
             mock.patch.object(zm, "load_state", lambda name, default: cached if name == "updates.json" else default), \
             mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
            zm.cmd_status()
        self.assertEqual(emitted.get("updates"),
                         {"checked": 111, "engine": True, "lists": False, "presets": None, "latest": "v9"})

    def test_updates_check_engine(self):
        emitted, saved = {}, {}
        with mock.patch.object(zm, "load_record", lambda: {"version": "v0.0.1"}), \
             mock.patch.object(zm, "latest_release", lambda: {"version": "v9.9.9"}), \
             mock.patch.object(zm, "http_get", side_effect=zm.Fail("no net")), \
             mock.patch.object(zm, "load_state", lambda name, default: default), \
             mock.patch.object(zm, "save_state", lambda name, obj: saved.update({name: obj})), \
             mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
            zm.cmd_updates_check()
        self.assertTrue(emitted.get("ok"))
        self.assertTrue(emitted.get("engine"))
        self.assertEqual(emitted.get("latest"), "v9.9.9")
        self.assertIsNone(emitted.get("lists"))
        self.assertIsNone(emitted.get("presets"))
        self.assertEqual(saved["updates.json"]["latest"], "v9.9.9")

    def test_updates_check_total_failure(self):
        with mock.patch.object(zm, "load_record", lambda: None), \
             mock.patch.object(zm, "latest_release", side_effect=zm.Fail("no net")), \
             mock.patch.object(zm, "http_get", side_effect=zm.Fail("no net")), \
             mock.patch.object(zm, "load_state", lambda name, default: default):
            with self.assertRaises(zm.Fail):
                zm.cmd_updates_check()


class SecureDns(unittest.TestCase):
    def test_status_parses_resolv_conf(self):
        import tempfile
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            rc = __import__("os").path.join(tmp, "resolv.conf")
            with open(rc, "w", encoding="utf-8") as f:
                f.write("# comment\n \nnameserver 1.1.1.1\nnameserver 8.8.8.8 # tail\nsearch example.com\n")
            emitted = {}
            with mock.patch.object(zm, "read_nofollow", lambda path, cap: open(rc, encoding="utf-8").read() if path == "/etc/resolv.conf" else None), \
                 mock.patch.object(zm, "tool", lambda n: "/usr/bin/resolvectl" if n == "resolvectl" else None), \
                 mock.patch.object(zm, "unit_state", lambda u: {"ActiveState": "active"}), \
                 mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
                zm.cmd_dns(["status"])
            self.assertTrue(emitted.get("ok"))
            self.assertEqual(emitted.get("dns"), ["1.1.1.1", "8.8.8.8"])
            self.assertTrue(emitted.get("resolvedActive"))

    def test_flush_uses_resolvectl(self):
        from unittest import mock
        calls = []
        def fake_sh(*a, **kw):
            calls.append(a)
            return mock.Mock(returncode=0, stdout="", stderr="")
        emitted = {}
        with mock.patch.object(zm, "tool", lambda n: "/usr/bin/resolvectl" if n == "resolvectl" else None), \
             mock.patch.object(zm, "sh", fake_sh), \
             mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
            zm.cmd_dns(["flush"])
        self.assertTrue(emitted.get("flushed"))
        self.assertTrue(any("flush-caches" in a for a in calls[0]))

    def test_flush_no_tool(self):
        from unittest import mock
        with mock.patch.object(zm, "tool", lambda n: None):
            with self.assertRaises(zm.Fail):
                zm.cmd_dns(["flush"])


class StrategyImport(unittest.TestCase):
    def _var(self, tmp):
        var = os.path.join(tmp, "var")
        os.makedirs(os.path.join(var, "custom"))
        return var

    def _strategy(self, var, args, stdin=None):
        emitted = {}
        patches = [mock.patch.object(zm, "require_installed", lambda: None),
                   mock.patch.object(zm, "VAR", var),
                   mock.patch.object(zm, "out", lambda obj: emitted.update(obj))]
        if stdin is not None:
            patches.append(mock.patch.object(zm, "read_stdin", lambda cap: stdin))
        for p in patches:
            p.start()
        try:
            zm.cmd_strategy(list(args))
        finally:
            for p in patches:
                p.stop()
        return emitted

    def test_import_stdin_ok(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            res = self._strategy(var, ["import"], stdin=MINIMAL)
            self.assertTrue(res.get("ok"))
            self.assertEqual(res.get("name"), "my-import")
            with open(os.path.join(var, "custom", "my-import.txt"), encoding="utf-8") as f:
                zm.parse_preset(f.read())
            res = self._strategy(var, ["import", "--name", "second"], stdin=MINIMAL)
            self.assertEqual(res.get("name"), "my-second")

    def test_import_bad_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            with self.assertRaises(zm.Fail):
                self._strategy(var, ["import"], stdin="[TCP_TLS]\n--lua-desync=luaexec:code=1\n" + MINIMAL)
            self.assertEqual(os.listdir(os.path.join(var, "custom")), [])

    def test_import_oversize_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            big = os.path.join(tmp, "big.txt")
            with open(big, "w", encoding="utf-8") as f:
                f.write(MINIMAL + "# pad\n" * 20000)
            with self.assertRaises(zm.Fail):
                self._strategy(var, ["import", big])
            self.assertEqual(os.listdir(os.path.join(var, "custom")), [])

    def test_import_file_ok(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            src = os.path.join(tmp, "s.txt")
            with open(src, "w", encoding="utf-8") as f:
                f.write(MINIMAL)
            res = self._strategy(var, ["import", src])
            self.assertEqual(res.get("name"), "my-import")

    def test_import_evil_file_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            src = os.path.join(tmp, "evil.txt")
            with open(src, "w", encoding="utf-8") as f:
                f.write(MINIMAL.replace("[TCP_TLS]\n", "[TCP_TLS]\n--user=root\n", 1))
            with self.assertRaises(zm.Fail):
                self._strategy(var, ["import", "--name", "evil", src])
            self.assertFalse(os.path.exists(os.path.join(var, "custom", "my-evil.txt")))

    def test_import_url_stdin_ok(self):
        # The link arrives on stdin, so a signed URL never appears in argv.
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            seen = []
            emitted = {}
            with mock.patch.object(zm, "require_installed", lambda: None), \
                 mock.patch.object(zm, "VAR", var), \
                 mock.patch.object(zm, "read_stdin", lambda cap: "https://example.com/s.txt?token=secret\n"), \
                 mock.patch.object(zm, "fetch_strategy_url", lambda url: seen.append(url) or MINIMAL), \
                 mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
                zm.cmd_strategy(["import", "--url-stdin", "--name", "signed"])
            self.assertEqual(seen, ["https://example.com/s.txt?token=secret"])
            self.assertEqual(emitted.get("name"), "my-signed")

    def test_import_url_stdin_rejects_non_link(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            with self.assertRaises(zm.Fail):
                self._strategy(var, ["import", "--url-stdin"], stdin="ftp://example.com/s.txt\n")
            with self.assertRaises(zm.Fail):
                self._strategy(var, ["import", "--url-stdin", "/tmp/x"], stdin="https://example.com/s\n")

    def test_fetch_bad_scheme_rejected(self):
        with self.assertRaises(zm.Fail):
            zm.fetch_strategy_url("ftp://example.com/s.txt")

    def test_import_bad_scheme_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            with self.assertRaises(zm.Fail):
                self._strategy(var, ["import", "ftp://example.com/s.txt"])

    def test_copy_ok(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            with open(os.path.join(var, "custom", "my-own.txt"), "w", encoding="utf-8") as f:
                f.write(MINIMAL)
            res = self._strategy(var, ["copy", "my-own"])
            self.assertTrue(res.get("ok"))
            self.assertEqual(res.get("name"), "my-own-copy")
            with open(os.path.join(var, "custom", "my-own-copy.txt"), encoding="utf-8") as f:
                self.assertEqual(f.read().strip(), MINIMAL.strip())
            res = self._strategy(var, ["copy", "my-own", "twin"])
            self.assertEqual(res.get("name"), "my-twin")

    def test_copy_foreign_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            for src in ("fs-general", "general", "custom-safe"):
                with self.subTest(src=src):
                    with self.assertRaises(zm.Fail):
                        self._strategy(var, ["copy", src])

    def test_copy_bad_name_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            with open(os.path.join(var, "custom", "my-own.txt"), "w", encoding="utf-8") as f:
                f.write(MINIMAL)
            with self.assertRaises(zm.Fail):
                self._strategy(var, ["copy", "my-own", "Bad Name!!"])
            with self.assertRaises(zm.Fail):
                self._strategy(var, ["copy", "my-missing"])


class Diagnostics(unittest.TestCase):
    def test_redacted_no_hosts_or_ips(self):
        import tempfile
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            var = __import__("os").path.join(tmp, "var")
            state = __import__("os").path.join(tmp, "state")
            __import__("os").makedirs(var)
            __import__("os").makedirs(state)
            emitted = {}
            with mock.patch.object(zm, "VAR", var), \
                 mock.patch.object(zm, "state_dir", lambda: state), \
                 mock.patch.object(zm, "load_record", lambda: {"version": "v1.2.3"}), \
                 mock.patch.object(zm, "unit_state", lambda u: {"ActiveState": "active", "SubState": "running", "NRestarts": "0"}), \
                 mock.patch.object(zm, "journal", lambda n, unit=None: ["Oct 06 10:00:00 h proc[1]: from 192.168.1.1 to 8.8.8.8 youtube.com ok"]), \
                 mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
                zm.cmd_diagnostics()
            self.assertTrue(emitted.get("ok"))
            text = emitted.get("text", "")
            self.assertIn("v1.2.3", text)
            self.assertNotIn("192.168.1.1", text)
            self.assertNotIn("8.8.8.8", text)
            self.assertNotIn("youtube.com", text)
            self.assertIn("[IP]", text)
            self.assertIn("[host]", text)

    def test_redact_ips(self):
        self.assertEqual(zm.redact_ips("a 1.2.3.4 b"), "a [IP] b")
        self.assertNotIn("::1", zm.redact_ips("x 2001:db8::1 y"))
        self.assertIn("10:00:00", zm.redact_ips("Oct 06 10:00:00 h ok"))
        self.assertNotIn("youtube.com", zm.redact_ips("open youtube.com now"))

    def test_report_shape_redacted(self):
        import os as _os
        import tempfile
        from unittest import mock
        home = _os.path.expanduser("~")
        with tempfile.TemporaryDirectory() as tmp:
            var = _os.path.join(tmp, "var")
            state = _os.path.join(tmp, "state")
            _os.makedirs(_os.path.join(var, "custom"))
            _os.makedirs(_os.path.join(var, "lists"))
            with open(_os.path.join(var, "custom", "my-x.txt"), "w", encoding="utf-8") as f:
                f.write(MINIMAL)
            with open(_os.path.join(var, "lists", "list-general-user.txt"), "w", encoding="utf-8") as f:
                f.write("secret.example.com\n10.9.9.9\n")
            emitted = {}
            with mock.patch.object(zm, "VAR", var), \
                 mock.patch.object(zm, "state_dir", lambda: state), \
                 mock.patch.object(zm, "load_record", lambda: {"version": "v1.2.3"}), \
                 mock.patch.object(zm, "unit_state", lambda u: {"ActiveState": "active", "SubState": "running", "NRestarts": "0"}), \
                 mock.patch.object(zm, "journal", lambda n, unit=None: ["log from %s/.config/x" % home]), \
                 mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
                zm.cmd_diagnostics()
            text = emitted.get("text", "")
            self.assertTrue(emitted.get("ok"))
            self.assertIn("v1.2.3", text)                    # engine version
            self.assertIn("doctor: Setup=", text)            # doctor statuses
            self.assertIn("my-x", text)                      # own strategy names…
            self.assertIn("list-general-user=2", text)       # …and list counts…
            self.assertNotIn("secret.example.com", text)     # …but no contents
            self.assertNotIn("10.9.9.9", text)
            self.assertNotIn(home, text)                     # home shortened to ~
            self.assertIn("~", text)


class Services(unittest.TestCase):
    def _var(self, tmp):
        import os
        var = os.path.join(tmp, "var")
        os.makedirs(os.path.join(var, "lists"), exist_ok=True)
        return var

    def test_all_domains_valid(self):
        for name, domains in zm.SERVICES.items():
            with self.subTest(service=name):
                self.assertTrue(domains)
                for d in domains:
                    self.assertTrue(zm.RE_DOMAIN.match(d), d)

    def test_on_off(self):
        import os, tempfile
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            emitted = {}
            with mock.patch.object(zm, "VAR", var), \
                 mock.patch.object(zm, "require_installed", lambda: None), \
                 mock.patch.object(zm, "restart_if_active", lambda: False), \
                 mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
                zm.cmd_service(["on", "telegram"])
            self.assertTrue(emitted.get("ok"))
            with open(os.path.join(var, "lists", "list-general-user.txt"), encoding="utf-8") as f:
                content = f.read()
            for d in zm.SERVICES["telegram"]:
                self.assertIn(d, content)
            emitted = {}
            with mock.patch.object(zm, "VAR", var), \
                 mock.patch.object(zm, "require_installed", lambda: None), \
                 mock.patch.object(zm, "restart_if_active", lambda: False), \
                 mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
                zm.cmd_service(["off", "telegram"])
            with open(os.path.join(var, "lists", "list-general-user.txt"), encoding="utf-8") as f:
                self.assertNotIn("t.me", f.read())

    def test_on_idempotent_keeps_others(self):
        import os, tempfile
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            with open(os.path.join(var, "lists", "list-general-user.txt"), "w", encoding="utf-8") as f:
                f.write("example.com\n")
            def run(*a):
                with mock.patch.object(zm, "VAR", var), \
                     mock.patch.object(zm, "require_installed", lambda: None), \
                     mock.patch.object(zm, "restart_if_active", lambda: False), \
                     mock.patch.object(zm, "out", lambda obj: None):
                    zm.cmd_service(list(a))
            run("on", "telegram")
            run("on", "telegram")
            with open(os.path.join(var, "lists", "list-general-user.txt"), encoding="utf-8") as f:
                lines = [l for l in f.read().splitlines() if l.strip()]
            self.assertIn("example.com", lines)
            self.assertEqual(len(lines), len(set(lines)))
            self.assertEqual(sorted(lines),
                             sorted(set(["example.com"] + zm.SERVICES["telegram"])))
            run("off", "telegram")
            with open(os.path.join(var, "lists", "list-general-user.txt"), encoding="utf-8") as f:
                self.assertEqual(f.read().splitlines(), ["example.com"])

    def test_unknown_rejected(self):
        import tempfile
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            with mock.patch.object(zm, "VAR", var), \
                 mock.patch.object(zm, "require_installed", lambda: None):
                with self.assertRaises(zm.Fail):
                    zm.cmd_service(["on", "no-such"])

    def test_services_list(self):
        import tempfile
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            var = self._var(tmp)
            emitted = {}
            with mock.patch.object(zm, "VAR", var), \
                 mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
                zm.cmd_services()
            self.assertTrue(emitted.get("ok"))
            names = [s["name"] for s in emitted["services"]]
            self.assertIn("telegram", names)
            self.assertIn("whatsapp", names)
            self.assertIn("rutracker", names)


class FirstRun(unittest.TestCase):
    def test_steps(self):
        import tempfile
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            state = __import__("os").path.join(tmp, "state")
            __import__("os").makedirs(state)
            emitted = {}
            with mock.patch.object(zm, "state_dir", lambda: state), \
                 mock.patch.object(zm, "installed", lambda: False), \
                 mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
                zm.cmd_first_run()
            self.assertEqual((emitted["installed"], emitted["autopicked"], emitted["done"]), (False, False, False))
            with open(os.path.join(state, "autopick.json"), "w", encoding="utf-8") as f:
                f.write('{"time": 123, "chosen": "general"}')
            emitted = {}
            with mock.patch.object(zm, "state_dir", lambda: state), \
                 mock.patch.object(zm, "installed", lambda: True), \
                 mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
                zm.cmd_first_run()
            self.assertEqual((emitted["installed"], emitted["autopicked"], emitted["done"]), (True, True, True))


if __name__ == "__main__":
    unittest.main()


class CircularPlan(unittest.TestCase):
    def test_plan_when_every_domain_resolves(self):
        # Regression: with nothing left for blockcheck2, the plan crashed on
        # list.values() instead of writing the config.
        with tempfile.TemporaryDirectory() as tmp:
            emitted = {}
            ok = {"categories": {"web": {"results": [{"url": "https://a.example/", "ok": True}]}}}
            with mock.patch.object(zm, "require_installed", lambda: None), \
                 mock.patch.object(zm, "VAR", tmp), \
                 mock.patch.object(zm, "all_presets", lambda: [{"name": "alt", "group": "flowseal"}]), \
                 mock.patch.object(zm, "circular_domains", lambda: ["a.example"]), \
                 mock.patch.object(zm, "unit_state", lambda u: {"ActiveState": "inactive"}), \
                 mock.patch.object(zm, "systemctl", lambda verb, unit: None), \
                 mock.patch.object(zm, "wait_active", lambda *a, **k: None), \
                 mock.patch.object(zm, "run_checks", lambda *a, **k: ok), \
                 mock.patch.object(zm, "progress", lambda **k: None), \
                 mock.patch.object(zm, "out", lambda obj: emitted.update(obj)):
                zm.cmd_circular(["plan"])
            self.assertTrue(emitted.get("ok"))
            self.assertFalse(emitted.get("needsBlockcheck"))
            self.assertEqual(emitted["config"]["blockcheck"], {"quick": {}, "standard": {}})


class CircularStrategy(unittest.TestCase):
    SCORES = {"a.example": {"alt": {"ok": 3, "total": 3}, "alt3": {"ok": 2, "total": 3},
                            "general": {"ok": 1, "total": 3}, "fs-general": {"ok": 3, "total": 3},
                            "alt5": {"ok": 3, "total": 3}, "simple-fake": {"ok": 0, "total": 3}}}

    def test_builds_a_rotation_from_plain_presets(self):
        text, names = zm.circular_strategy(self.SCORES)
        # alt5 has its own --payload lines, fs-* are full presets, simple-fake scored 0
        self.assertEqual(names, ["alt", "alt3", "general"])
        sections = zm.parse_preset(text)  # passes the same validation the root side applies
        for sec in zm.REQUIRED:
            lines = sections[sec]
            self.assertEqual(lines[0], "--in-range=-s34228")
            self.assertEqual(lines[1], "--lua-desync=circular:fails=3:time=60")
            tags = sorted({l.rsplit(":strategy=", 1)[1] for l in lines[2:]})
            self.assertEqual(tags, ["1", "2", "3"])

    def test_needs_two_presets(self):
        self.assertIsNone(zm.circular_strategy({"a.example": {"alt": {"ok": 3, "total": 3}}})[0])

    def test_circular_arguments_stay_numeric(self):
        for bad in ("circular:success_detector=luaexec", "circular:fails=x", "circular:hostkey=f",
                    "fake:strategy=x", "fake:strategy=10"):
            with self.assertRaises(zm.Fail):
                zm.check_desync(bad)
        zm.check_desync("circular:fails=3:time=60")
        zm.check_desync("fake:blob=tls_google:strategy=2")

    def test_measured_row_joins_the_pick_list(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = {}
            row = {"preset": "my-circular", "score": 9, "total": 14, "categories": {}}
            with mock.patch.object(zm, "load_state", lambda n, d: state.get(n, d)), \
                 mock.patch.object(zm, "save_state", lambda n, o: state.__setitem__(n, o)):
                self.assertFalse(zm.merge_autopick_row(row))          # no earlier pick: nothing to compare against
                state["autopick.json"] = {"rows": [{"preset": "alt", "score": 5, "total": 14},
                                                   {"preset": "my-circular", "score": 1, "total": 14}],
                                          "baseline": {"preset": "(off)", "score": 4, "total": 14}, "chosen": "alt"}
                self.assertTrue(zm.merge_autopick_row(row))
            rows = state["autopick.json"]["rows"]
            self.assertEqual([r["preset"] for r in rows], ["alt", "my-circular"])
            self.assertEqual(rows[-1]["score"], 9)                    # replaced, not duplicated

    def test_zapret_auto_helpers_stay_out(self):
        # zapret-auto.lua is loaded whenever a strategy uses circular, so its
        # other functions must stay unreachable by name.
        for fn in ("luaexec", "condition", "per_instance_condition", "stopif", "cond_lua",
                   "argdebug", "standard_hostkey", "standard_failure_detector"):
            with self.assertRaises(zm.Fail):
                zm.check_desync(fn)

    def test_circular_only_in_section_strategies(self):
        # the full-profile renderer does not load zapret-auto.lua
        with self.assertRaises(zm.Fail):
            zm.check_line("--lua-desync=circular:fails=3", "FULL")
        zm.check_line("--lua-desync=circular:fails=3", "TCP_TLS")

    def test_render_loads_zapret_auto_only_for_circular(self):
        text, _ = zm.circular_strategy(self.SCORES)
        settings = dict(zm.DEFAULTS)
        counts = {n: 1 for n in zm.BASE_LISTS}
        for body, expected in ((text, True), (open(os.path.join(zm.DATA, "presets", "alt.txt")).read(), False)):
            args = zm.render_args("my-x", zm.parse_preset(body), settings, "/E", "/L", ["/F"], counts)
            self.assertEqual("--lua-init=@/E/lua/zapret-auto.lua" in args, expected)
