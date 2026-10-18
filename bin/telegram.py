"""User-only Telegram WS proxy integration. Loaded by the manager with its IO helpers."""
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import socket
import tarfile
import time

UNIT = "omarchy-zapret2-telegram.service"
BASE = Path.home() / ".local/share/omarchy-zapret2/telegram"
UNIT_PATH = Path.home() / ".config/systemd/user" / UNIT
REVISION = "307a384ab7f522e34bb1a045884d0bd90f40bee5"
ARCHIVE_SHA = "db9048b56faaf64f43f1a4f4833e45ad4ba8a7b1ee27c8ed5f7f4467db7326d1"
API = "https://api.github.com/repos/Flowseal/tg-ws-proxy/commits/main"


def read_json(name, default):
    try:
        with (BASE / name).open("rb") as f:
            data = f.read(65537)
        if len(data) > 65536:
            raise Fail("Telegram configuration is too large")
        return json.loads(data)
    except FileNotFoundError:
        return default
    except (ValueError, OSError) as e:
        raise Fail("Cannot read Telegram configuration: %s" % e)


def write_json(name, data):
    BASE.mkdir(parents=True, exist_ok=True, mode=0o700)
    atomic_write(str(BASE / name), json.dumps(data), mode=0o600)


def config(create=False):
    c = read_json("settings.json", {"port": 1443, "secret": ""})
    if (not isinstance(c, dict) or type(c.get("port")) is not int
            or not 1024 <= c["port"] <= 65535
            or not isinstance(c.get("secret"), str)
            or (c["secret"] and not re.fullmatch(r"[0-9a-f]{32}", c["secret"]))):
        raise Fail("Invalid Telegram configuration")
    if create and not c["secret"]:
        c["secret"] = os.urandom(16).hex()
        write_json("settings.json", c)
    return c


def engine():
    m = read_json("engine.json", {})
    if (not isinstance(m, dict) or not isinstance(m.get("revision"), str)
            or not re.fullmatch(r"[0-9a-f]{40}", m["revision"])):
        return None
    p = BASE / "engines" / m["revision"] / "venv/bin/python"
    return (m, p) if p.is_file() else None


def ctl(*args, required=True):
    r = sh("systemctl", "--user", *args, timeout=30)
    if required and r.returncode:
        raise Fail("Telegram service: " + (r.stderr.strip() or r.stdout.strip() or "systemctl failed"))
    return r


def state():
    e, c = engine(), config()
    result = {"installed": bool(e), "active": "inactive", "autostart": False,
              "port": c["port"], "version": e[0].get("version", "") if e else "",
              "revision": e[0]["revision"] if e else "", "check": read_json("check.json", {})}
    if e or UNIT_PATH.exists():
        r = ctl("show", UNIT, "--property=ActiveState,UnitFileState", required=False)
        values = dict(line.split("=", 1) for line in r.stdout.splitlines() if "=" in line)
        result["active"] = values.get("ActiveState", "unknown")
        result["autostart"] = values.get("UnitFileState") == "enabled"
        if r.returncode:
            result["error"] = r.stderr.strip() or "User systemd is unavailable"
    return result


def redact(text):
    text = re.sub(r"(?i)(secret[=: ]+)(?:dd|ee)?[0-9a-f]{32,}", r"\1[redacted]", text)
    return re.sub(r"(?i)([?&]secret=)[^\s&]+", r"\1[redacted]", text)


def unit_text():
    # systemd specifier and quote escaping, not shell escaping.
    executable = SELF.replace("%", "%%").replace("\\", "\\\\").replace('"', '\\"')
    return ('[Unit]\nDescription=Zapret2 Telegram WebSocket proxy\n'
            'After=network-online.target\n\n[Service]\nType=simple\n'
            'ExecStart="%s" telegram run\nRestart=on-failure\nRestartSec=5\n'
            'TimeoutStopSec=10\nNoNewPrivileges=yes\nPrivateTmp=yes\n'
            'UMask=0077\n\n[Install]\nWantedBy=default.target\n') % executable


def install(update=False):
    old = engine()
    revision = REVISION
    if update:
        try:
            revision = json.loads(http_get(API, 1024 * 1024))["sha"]
        except (KeyError, TypeError, ValueError):
            raise Fail("Invalid Telegram upstream revision")
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise Fail("Invalid Telegram upstream revision")
    out({"progress": True, "stage": "telegram", "message": "Загрузка прокси Telegram"})
    archive = http_get("https://codeload.github.com/Flowseal/tg-ws-proxy/tar.gz/" + revision,
                       16 * 1024 * 1024, timeout=60)
    digest = hashlib.sha256(archive).hexdigest()
    if revision == REVISION and digest != ARCHIVE_SHA:
        raise Fail("Telegram archive checksum mismatch")
    directory = BASE / "engines" / revision
    python = directory / "venv/bin/python"
    was_on = state()["active"] in ("active", "activating")
    # Build at its final path: venv launchers contain absolute paths.
    # An installed revision is immutable; never modify the running engine.
    if not old or old[0]["revision"] != revision:
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir(parents=True)
        try:
            source = directory / "source"
            source.mkdir()
            with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as tar:
                total = 0
                for member in tar:
                    parts = Path(member.name).parts[1:]
                    if not parts or parts[0] != "proxy" or not member.isfile():
                        continue
                    if any(p in ("..", ".") for p in parts) or member.size > 2 * 1024 * 1024:
                        raise Fail("Unsafe Telegram archive")
                    total += member.size
                    if total > 16 * 1024 * 1024:
                        raise Fail("Telegram source is too large")
                    dest = source.joinpath(*parts)
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    with tar.extractfile(member) as f:
                        dest.write_bytes(f.read())
                # Keep the upstream license beside its source.
                license_member = next((m for m in tar.getmembers()
                                       if m.name.endswith("/LICENSE") and m.isfile() and m.size < 65536), None)
                if license_member:
                    (directory / "LICENSE").write_bytes(tar.extractfile(license_member).read())
            r = sh("/usr/bin/python3", "-m", "venv", str(directory / "venv"), timeout=60)
            if r.returncode:
                raise Fail("Cannot create Telegram Python environment: " + r.stderr[-2000:])
            out({"progress": True, "stage": "telegram", "message": "Установка зависимостей Telegram"})
            r = sh(str(python), "-I", "-m", "pip", "install", "--disable-pip-version-check",
                   "cryptography==46.0.5", "httpx[http2]==0.28.1", "certifi", timeout=240)
            if r.returncode:
                raise Fail("Cannot install Telegram dependencies: " + redact(r.stderr[-2000:]))
            # Only the headless proxy package is needed; no Tk/tray dependencies.
            r = sh(str(python), "-I", "-c", "import sys; sys.path.insert(0, sys.argv[1]); "
                   "import proxy.tg_ws_proxy; import proxy; print(proxy.__version__)", str(source), timeout=30)
            if r.returncode:
                raise Fail("Telegram engine verification failed: " + r.stderr[-2000:])
            version = r.stdout.strip()
        except BaseException:
            shutil.rmtree(directory, ignore_errors=True)
            raise
    else:
        version = old[0].get("version", "")
    meta = {"revision": revision, "version": version, "sha256": digest}
    config(create=True)
    previous_unit = UNIT_PATH.read_text() if UNIT_PATH.exists() else None
    try:
        write_json("engine.json", meta)
        atomic_write(str(UNIT_PATH), unit_text(), mode=0o600)
        ctl("daemon-reload")
        if was_on:
            ctl("restart", UNIT)
            wait_ready()
    except BaseException:
        write_json("engine.json", old[0] if old else {})
        if previous_unit is not None:
            atomic_write(str(UNIT_PATH), previous_unit, mode=0o600)
        else:
            UNIT_PATH.unlink(missing_ok=True)
        ctl("daemon-reload", required=False)
        if was_on and old:
            ctl("restart", UNIT, required=False)
        raise
    write_json("check.json", {})
    return {"version": version, "revision": revision}


def require_engine():
    e = engine()
    if not e:
        raise Fail("Install the Telegram proxy first")
    return e


def port_free(port):
    try:
        with socket.socket() as s:
            # Match asyncio.start_server: closed connections in TIME_WAIT
            # must not prevent restarting the listener on the same port.
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(("127.0.0.1", port))
    except OSError:
        raise Fail("Telegram port %s is already in use" % port)


def wait_ready():
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if ctl("is-active", UNIT, required=False).stdout.strip() == "active":
            try:
                with socket.create_connection(("127.0.0.1", config()["port"]), timeout=0.3):
                    return
            except OSError:
                pass
        time.sleep(0.2)
    raise Fail("Telegram proxy did not start; open Telegram logs")


# Set the secret inside the engine process, never in argv or journal output.
BOOTSTRAP = r'''
import json, logging, sys
sys.path.insert(0, sys.argv[1])
c = json.load(open(sys.argv[2]))
secret = c['secret']
factory = logging.getLogRecordFactory()
def record(*a, **kw):
    r = factory(*a, **kw)
    r.msg = r.getMessage().replace(secret, '[redacted]')
    r.args = ()
    return r
logging.setLogRecordFactory(record)
import proxy.tg_ws_proxy as p
p.start_cfproxy_domain_refresh = lambda: None
sys.argv = ['tg-ws-proxy', '--host', '127.0.0.1', '--port', str(c['port']),
            '--secret', secret, '--no-cfproxy', '--no-h2']
p.main()
'''

PROBE = r'''
import asyncio, json, sys
sys.path.insert(0, sys.argv[1])
from proxy.raw_websocket import RawWebSocket
async def probe(dc, media):
    domain = 'kws%d%s.web.telegram.org' % (dc, '-1' if media else '')
    try:
        ws = await asyncio.wait_for(RawWebSocket.connect('149.154.167.220', domain, timeout=5), 7)
        await ws.close()
        return {'dc': dc, 'media': media, 'ok': True}
    except Exception as e:
        return {'dc': dc, 'media': media, 'ok': False, 'error': str(e)[:200]}
async def main():
    return await asyncio.gather(*(probe(dc, media) for dc in (2, 4) for media in (False, True)))
print(json.dumps(asyncio.run(main())))
'''


def command(args):
    verb = args[0] if args else "status"
    if verb == "run" and len(args) == 1:
        e = require_engine()
        config(create=True)
        os.execv(str(e[1]), [str(e[1]), "-I", "-u", "-c", BOOTSTRAP,
                            str(e[1].parents[2] / "source"), str(BASE / "settings.json")])
    if verb == "status" and len(args) <= 1:
        return state()
    if verb == "logs" and len(args) == 1:
        r = sh("journalctl", "--user", "-u", UNIT, "-n", "120", "--no-pager", "-o", "short-iso", timeout=15)
        if r.returncode:
            raise Fail("Cannot read Telegram logs: " + r.stderr.strip())
        return {"lines": [redact(l) for l in r.stdout.splitlines()]}
    if verb == "link" and len(args) == 1:
        require_engine()
        c = config(create=True)
        return {"link": "tg://proxy?server=127.0.0.1&port=%d&secret=dd%s" % (c["port"], c["secret"])}
    if verb == "check" and len(args) == 1:
        e = require_engine()
        r = sh(str(e[1]), "-I", "-c", PROBE, str(e[1].parents[2] / "source"), timeout=12)
        if r.returncode:
            raise Fail("Telegram transport check failed: " + redact(r.stderr[-1000:]))
        try:
            results = json.loads(r.stdout)
        except ValueError:
            raise Fail("Invalid Telegram transport check response")
        report = {"at": int(time.time()), "results": results, "port": config()["port"],
                  "revision": e[0]["revision"]}
        write_json("check.json", report)
        return {"check": report}
    # One mutation at a time, including from another manager process.
    BASE.mkdir(parents=True, exist_ok=True, mode=0o700)
    with open(BASE / "action.lock", "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Fail("Another Telegram action is running")
        if verb in ("install", "update") and len(args) == 1:
            return install(update=verb == "update")
        if verb == "remove" and len(args) == 1:
            if UNIT_PATH.exists():
                ctl("disable", "--now", UNIT)
                UNIT_PATH.unlink()
                ctl("daemon-reload")
            shutil.rmtree(BASE / "engines", ignore_errors=True)
            write_json("engine.json", {})
            write_json("check.json", {})
            return {"removed": True}
        require_engine()
        if verb in ("on", "off", "restart") and len(args) == 1:
            if verb == "on" and state()["active"] not in ("active", "activating"):
                port_free(config()["port"])
            ctl({"on": "start", "off": "stop", "restart": "restart"}[verb], UNIT)
            if verb != "off":
                wait_ready()
            return {}
        if verb == "set" and len(args) == 3:
            key, value = args[1:]
            if key == "autostart" and value in ("on", "off"):
                ctl("enable" if value == "on" else "disable", UNIT)
                return {}
            if key == "port" and re.fullmatch(r"[0-9]{4,5}", value) and 1024 <= int(value) <= 65535:
                c = config(create=True)
                if c["port"] == int(value):
                    return {}
                port_free(int(value))
                previous = dict(c)
                c["port"] = int(value)
                was_on = state()["active"] in ("active", "activating")
                write_json("settings.json", c)
                try:
                    if was_on:
                        ctl("restart", UNIT)
                        wait_ready()
                except BaseException:
                    write_json("settings.json", previous)
                    if was_on:
                        ctl("restart", UNIT, required=False)
                    raise
                write_json("check.json", {})
                return {}
        raise Fail("usage: telegram status|install|update|on|off|restart|link|check|logs|remove|set port|autostart <value>")
