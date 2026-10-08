# Zapret2 for Omarchy

[zapret2](https://github.com/bol-van/zapret2) (DPI bypass by bol-van) as an
[Omarchy](https://omarchy.org) app: a window with strategies, lists, checks,
autopick and blockcheck2, plus a bar icon for quick on/off. The Windows GUIs
(zapret2gui, Zapret-2-GUI, zapret2UI) inspired the feature set; the strategy
presets are the Linux port of [Zapret 2 NEXT](https://github.com/Dunterbabochka/zapret2-next)
(which ports [Flowseal](https://github.com/Flowseal/zapret-discord-youtube)'s strategies to zapret2).

> Обход DPI для YouTube, Discord и других сайтов. Окно приложения
> открывается из лаунчера («Zapret2») или кликом по иконке-щиту в баре.

```
BarWidget.qml ─┐                         ┌─ omarchy-zapret2.service (root, hardened)
App.qml ───────┼─▶ Service.qml ─▶ bin/omarchy-zapret2 ─┤     /opt/omarchy-zapret2/app/bin/omarchy-zapret2 _run
               │   (shared state)  (JSON, as you)       │       └─ nft -f rules  ─▶ exec nfqws2 --user=nobody
               │                                        ├─ omarchy-zapret2-blockcheck.service (root) ─▶ blockcheck2.sh
               └────────────────────────────────────────┴─ pkexec, once: setup / engine update / removal
```

## Install

```bash
omarchy plugin add https://github.com/KRIEZIEYR/omarchy-zapret2.git --enable
```

Open **Zapret2** from the launcher (or click the padlock in the bar) and press
**Install**. The manager downloads the latest `zapret2-vX.tar.gz` from
bol-van/zapret2's GitHub releases, checks it against the sha256 digest GitHub
publishes for the asset, and asks for your password once (polkit). Then
switch it on.

## Dependencies

- Omarchy with shell plugins (Quickshell), x86_64 only (the release binary).
- `/usr/bin/python3`, `curl`, `nftables`, polkit — all part of Omarchy.
- The zapret2 engine itself (bol-van/zapret2, MIT) is downloaded from its
  GitHub releases on first install and verified by sha256.
- Optional: `bind` (`omarchy pkg add bind`) for the deep search (blockcheck2).

## Remove

Turn the bypass off, then remove the system part (asks for your password)
and the plugin:

```bash
~/.config/omarchy/plugins/krieziey.omarchy-zapret2/bin/omarchy-zapret2 remove --purge
omarchy plugin remove krieziey.omarchy-zapret2
```

`remove` deletes `/opt/omarchy-zapret2`, the systemd unit, the polkit rule and
the nftables table; `--purge` also deletes your lists and own strategies in
`/var/lib/omarchy-zapret2` (without it they are kept). The same action is in
the app under Движок → Удаление.

## What it does

- **Overview**: on/off, the active strategy, reachability of YouTube, Discord,
  Google and Cloudflare (TLS and, when curl has HTTP/3, QUIC) per URL.
- **Strategies**: Zapret 2 NEXT presets (shown with " · Z2", e.g. "General · Z2")
  and Flowseal presets (without suffix), plus your own, edited in the window.
- **Lists**: your sites, exclusions and IP networks; the bundled lists
  (read-only) and **Update from Flowseal** for fresh upstream lists. One
  domain per line covers its subdomains; `^domain` means that host only.
- **Search**: *quick autopick* tries the presets one by one and keeps the
  best (1–3 min, no password); *blockcheck2* runs zapret2's own exhaustive
  search (quick/standard/force) and lets you save a finding as a strategy.
- **Search** needs `host` or `nslookup` for blockcheck2: `omarchy pkg add bind`.
- **Engine**: version, engine update, update of the system copy after a plugin
  update, doctor, service log, removal.
- **Settings**: start at login, IPv6, game filter (TCP/UDP 1024–65535 by
  ipset), ipset mode, Discord voice mode.
- **Bar**: click for a popup (switch, strategy, last check), right-click
  toggles, middle-click opens the app. Bright filled shield when on, outline
  when off, a dot on errors.

## Security model

zapret2 has to run as root (NFQUEUE, raw sockets). The plugin keeps every root
process on root-owned code and treats what you can write as data:

| Path | Owner | What |
|---|---|---|
| `/opt/omarchy-zapret2/engine/<ver>/` (+ `current`) | root | the verified release: `nfq2/nfqws2`, `lua/`, `files/fake/`, `blockcheck2.sh` |
| `/opt/omarchy-zapret2/app/` | root | a copy of this manager and `data/` (presets, lists, templates) the units run |
| `/etc/systemd/system/omarchy-zapret2*.service` | root | the bypass and blockcheck units |
| `/etc/polkit-1/rules.d/49-omarchy-zapret2.rules` | root | **only your user**, active local session, may `start/stop/restart` **only these two units** without a password |
| `/opt/omarchy-zapret2/install.json` | root | uid and sha256 of every file written (doctor checks them) |
| `/var/lib/omarchy-zapret2/` | you | `settings.json`, your lists, your strategies, blockcheck request |

- The units run `/opt/omarchy-zapret2/app/bin/omarchy-zapret2`, never the
  plugin folder; that copy refuses to run from anywhere else.
- It reads `/var/lib/omarchy-zapret2` without following symlinks and only
  files you own. Settings are enums (anything else falls back to defaults).
  Lists are re-validated line by line (domains, IP/CIDR) into
  `/run/omarchy-zapret2`, so nfqws2 never opens your files.
- Strategies (bundled or yours) may contain only `--lua-desync`, `--payload`,
  `--out-range`, `--in-range` (and port/protocol filters in the voice block).
  Desync functions are limited to `zapret-antidpi.lua`: no `luaexec`, no
  `condition`/`orchestrate`, no `--lua-init`, `--blob=@file`, `--hostlist`,
  `--writable`, `--user`, `--debug`. Blob references must be known names.
- nfqws2 drops to `nobody` after start; the unit is sandboxed
  (`ProtectSystem=strict`, `ProtectHome`, `NoNewPrivileges`, capability
  bounding set `CAP_NET_ADMIN CAP_NET_RAW CAP_SETUID CAP_SETGID`).
- Its nftables table `inet omarchy_zapret2` sends only the first packets of
  connections (TCP 80/443/Discord media ports, UDP 443 and Discord voice, plus
  the game ranges when enabled) to queue 220, and is deleted when the service
  stops.
- Downloads are HTTPS only with size caps; the release must match GitHub's
  sha256 digest, verified again as root before extraction (tar `data` filter,
  an allowlist of paths).
- pkexec runs this script as root only for `setup`, `engine update`,
  `setup --app-only` and `remove`, each with a password prompt.

## Command line

The window covers everything. For a terminal:
`ln -s ~/.config/omarchy/plugins/krieziey.omarchy-zapret2/bin/omarchy-zapret2 ~/.local/bin/`

```bash
omarchy-zapret2 setup                 # install (download, verify, one prompt)
omarchy-zapret2 on | off | restart
omarchy-zapret2 status                # JSON
omarchy-zapret2 set preset alt5       # also: game off|tcp|udp|all, ipset loaded|none|any,
                                      # voice compatible|standard|off, ipv6 on|off, autostart on|off
omarchy-zapret2 check                 # reachability now
omarchy-zapret2 autopick              # or: autopick general,alt,alt5
omarchy-zapret2 blockcheck start youtube.com discord.com --level quick
omarchy-zapret2 blockcheck status | stop | save 0 [name]
echo example.org | omarchy-zapret2 list save list-general-user
omarchy-zapret2 custom save home < my-strategy.txt
omarchy-zapret2 lists update          # fresh lists from Flowseal
omarchy-zapret2 engine check | engine update
omarchy-zapret2 setup --app-only      # after a plugin update
omarchy-zapret2 doctor | logs [n]
omarchy-zapret2 remove [--purge]      # --purge also deletes /var/lib/omarchy-zapret2
```

Shell IPC (`omarchy-shell krieziey.omarchy-zapret2 VERB`): `toggle` / `open` /
`close` (window), `toggleBypass`, `on`, `off`, `status`, `strategy <name>`,
`check`, `autopick`. The bar popup has its own target:
`omarchy-shell krieziey.omarchy-zapret2-bar toggle`. For example in
`~/.config/hypr/bindings.lua`, bind `omarchy-shell krieziey.omarchy-zapret2 toggleBypass`.

## Own strategies

Sections of nfqws2 options, as in the presets (`data/presets/*.txt`):

```ini
[TCP_HTTP]
--lua-desync=fake:blob=http_iana:tcp_md5:repeats=6
--lua-desync=multisplit:pos=2,host+1
[TCP_TLS]
--lua-desync=fake:blob=tls_google:tcp_md5:repeats=6
--lua-desync=multisplit:pos=2,midsld
[TCP_GENERIC]
--lua-desync=fake:blob=tls_google:tcp_md5:repeats=4
--lua-desync=multisplit:pos=2
[QUIC]
--lua-desync=fake:blob=quic_google:repeats=6
```

Optional: `[GOOGLE_TLS]`, `[DISCORD_MEDIA_TLS]`, `[DISCORD_WEB_TLS]`
(default to `[TCP_TLS]`), `[IPSET_TCP_PORTS]`, `[VOICE_COMPATIBLE]`. Blobs:
`tls_google`, `tls_max`, `quic_google`, `http_iana`, `stun`, `zero`,
`discord_voice`, `game_udp`, `fake_default_tls/http/quic`, or `0x…` hex.

## Troubleshooting

- **Doctor** (Engine tab) checks setup, file hashes, the system copy, nfqws2,
  nft, curl, other zapret services and an active omarchy-xray TUN (traffic in a
  VPN tunnel is not affected by the bypass).
- Logs: the Engine tab or `omarchy-zapret2 logs`. Reading system logs needs
  the `wheel` or `systemd-journal` group (the Omarchy user has it).
- Nothing opens: run **Quick autopick**, then blockcheck2 with your domains.

## Development

```bash
node tests/run.js
python3 -m unittest discover -s tests/manager
OMARCHY_ZAPRET2_TEST_ENGINE=/path/to/zapret2-vX python3 -m unittest discover -s tests/manager  # + nfqws2 --dry-run of every preset
omarchy plugin validate "$PWD"
```

Run from a checkout: `ln -s "$PWD" ~/.config/omarchy/plugins/krieziey.omarchy-zapret2 && omarchy-shell shell rescanPlugins && omarchy plugin enable krieziey.omarchy-zapret2 right`.
After a manager change run `omarchy-zapret2 setup --app-only` so the units get the new copy.
The shell does not notice edits through the symlink: run `omarchy restart shell` after QML changes.

## Credits and licenses

MIT. zapret2 by bol-van (MIT, downloaded at install time, not bundled).
Presets, lists and the extra fake payloads in `data/` come from Zapret 2 NEXT
(MIT, `data/LICENSE.zapret2-next.txt`), which builds on Flowseal's
zapret-discord-youtube (MIT).
