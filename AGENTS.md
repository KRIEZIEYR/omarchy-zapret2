# AGENTS.md — omarchy-zapret2

Handoff notes for coding agents (opencode, Antigravity, Claude). Read this, then
PRODUCT.md, before touching anything.

## What this is

An Omarchy shell plugin `krieziey.omarchy-zapret2` that manages the zapret2 DPI
bypass engine (bol-van/zapret2, `nfqws2` + Lua desync) on Arch/Omarchy. UI is
Quickshell/QML inside the Omarchy shell; logic lives in a Python manager.
UI copy: English by default, Russian via Settings → Language. Russian source
strings are wrapped in `root.t()` (QML) / `tr()` (model) and translated by
`model/En.js`; add every new Russian string there. Repo: https://github.com/KRIEZIEYR/omarchy-zapret2, branch
`master`.

## Layout

- `manifest.json` — kinds service + panel + bar-widget.
- `Service.qml` — shared state; polls the manager, runs actions (`act`).
- `App.qml` — the app: a normal Hyprland `FloatingWindow` (not an overlay)
  with 6 tabs: Обзор, Стратегии, Списки, Подбор, Движок, Настройки.
- `BarWidget.qml` — bar icon + popup (toggle, strategy, check, open app).
- `ZapretIcon.qml` — shield drawn on Canvas.
- `model/Zapret.js` — pure logic (titles, verdicts, colors, parsing). Every
  exported function used by tests is listed in `tests/run.js`.
- `bin/omarchy-zapret2` — Python manager (`python3 -I`), JSON on stdout.
  Commands: status, presets/presets show/presets update, on/off/restart,
  set <key> <value>, custom, list, lists update, hosts, discord-cache,
  check, autopick, blockcheck, engine check/update, setup [--app-only],
  remove [--purge], logs, doctor, plus root-only run/stop/blockcheck-run.
- `data/presets/flowseal/*.txt` — 22 Flowseal `general*.bat` strategies
  translated winws -> nfqws2 (`fs-*`); Zapret 2 NEXT presets; `data/lists`,
  `data/targets.json`, fake blobs.
- `tests/run.js` (node, model tests), `tests/manager/test_manager.py`.

## Security model (do not break)

- Root only runs root-owned code from `/opt/omarchy-zapret2` (installed copy
  of this repo + engine), systemd unit `omarchy-zapret2@.service`, polkit rule.
- `/var/lib/omarchy-zapret2` (settings, user lists, `my-*` strategies) is user
  writable and is treated as untrusted DATA: validated by allowlists
  (`parse_preset`, `check_line`, `clean_list`). Never allow free-form nfqws2
  args, arbitrary Lua, `--blob=@file`, `luaexec`, or paths outside the engine.
- nftables queue 220, own table `inet omarchy_zapret2`; tunnels skipped via
  `oiftype 65534` (user runs omarchy-xray VPN).

## Running and checking

- Tests: `node tests/run.js` and `python3 -m unittest discover -s tests/manager`
  must pass. `python3 -m py_compile bin/omarchy-zapret2`.
- The plugin dir `~/.config/omarchy/plugins/krieziey.omarchy-zapret2` symlinks
  to this repo, but the shell does NOT hot-reload QML through it: run
  `omarchy restart shell` after QML edits.
- Open a tab: `omarchy-shell shell summon krieziey.omarchy-zapret2 '{"tab":N}'`
  (N = 0..5). Window title is `Zapret2`; screenshot with
  `grim -g "<x>,<y> <w>x<h>"` using geometry from `hyprctl clients -j`.
- Runtime QML errors: `journalctl --user --since "-1min" | grep App.qml`.
- Root-side changes (manager code run as root, unit, nft rendering) only take
  effect after the USER runs `omarchy-zapret2 setup --app-only` (password).
  The installed system copy is currently older than the repo.

## QML pitfalls in this Qt version (all hit before)

- No nested inline `component` declarations; use `Component { id }`.
- Inside a `Card { id: x }` instance, reference its custom properties from
  children as `x.prop`, not bare `prop`.
- No `anchors` on items managed by a Layout.
- `Accessible.expanded` does not exist; put state into `Accessible.name`.
- Window size: `minimumSize`/`maximumSize: Qt.size(...)`, not maximumWidth.
- ScrollView: never bind `contentWidth`; give the child
  `width: <scrollViewId>.availableWidth` (otherwise it collapses to a narrow
  column — this broke the Strategies tab once).
- QML color channels are 0..1 (see `mixColor`); `root.dim`, `root.dimmer`,
  `root.bad`, `root.fg`, `Color.accent` are the only colors to use.
- Use kit components from `qs.Ui` (PanelHero, CursorSurface, Toggle,
  PrimaryButton, Button{bordered}, PanelSectionHeader, BorderSurface...).

## User preferences (explicit, from the owner)

- Works autonomously; don't stop to ask what next. Commit + push after each
  verified step (`git push` to master).
- Hates noise text. Removed on request, do not bring back: "NEXT ·" title
  prefix (Zapret 2 presets now end with " · Z2"), QUIC/HTTP3 warnings
  (http3 probes are ignored in counts), "= без обхода" / "как без обхода" /
  "открывается не хуже… VPN" tie labels, "Показать стратегии" collapse —
  the strategy list is always fully expanded.
- The owner's network already bypasses DPI (router + VPN), so every strategy
  ties with the no-bypass baseline there; efficacy can't be tested locally.
- One primary (filled) button per card; others bordered.

## Roadmap

Done: backup/restore, single-domain check, opt-in update check, DNS helper,
redacted diagnostics, strategy import/copy, per-service hosts, first-run flow,
fake blob choice (discordFake/gameFake), circular per-host plan (zapret-auto).
Open, low value until someone asks: per-list enable/disable (root-side render),
recheck on network change.
Rejected: free-form nfqws args/Lua editor, VPN subscriptions, LAN proxy
sharing, Telegram ratings.
Note: the youtubediscord "Zapret 2 GUI" (git.zapret.moe) was reported on
Habr for malware-like behaviour — take ideas only, never its code.
