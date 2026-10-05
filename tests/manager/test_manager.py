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


if __name__ == "__main__":
    unittest.main()
