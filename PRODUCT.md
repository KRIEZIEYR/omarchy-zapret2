# Product

<!-- impeccable:product-schema 1 -->

## Platform

desktop

Desktop Linux inside the Omarchy shell (Quickshell/QML on Hyprland): a regular
Hyprland window for the app and a popup on the Omarchy bar. Mouse and keyboard;
theme, fonts and components come from the shell (`qs.Commons`, `qs.Ui`).

## Users

People running Omarchy in Russia whose ISP throttles or blocks YouTube,
Discord and similar services with DPI. They want the bypass switched on and
then forgotten: no hand-editing zapret configs, no `.bat` files, no reading
the zapret manual.

## Product Purpose

Install the official zapret2 engine (bol-van/zapret2) with one password
prompt, pick a strategy that works on the user's network, and keep it running.
Success: YouTube and Discord open, and nothing else breaks, without the user
ever touching nfqws2 options.

## Positioning

- Every current Flowseal (zapret-discord-youtube) `general*.bat` strategy,
  translated from winws/zapret1 to nfqws2 and updatable from the upstream repo.
- Picks the strategy for the user's ISP: quick autopick against a no-bypass
  baseline, and zapret2's own blockcheck2 for a deep search.
- Native to Omarchy: shell theme, bar widget, launcher entry; no Electron, no
  extra processes besides the engine.
- Security first: root runs only root-owned code; everything the user can
  write (settings, lists, strategies) is validated as data.

## Operating Context

- Opened from the launcher ("Zapret2"), the bar shield icon (left click popup,
  right click on/off, middle click app) or `omarchy-shell` IPC and keybindings.
- Typical session: install once, run autopick, then only glance at the bar
  icon; return when a site stops opening (check, autopick again, edit lists).
- Often coexists with a VPN (omarchy-xray TUN); the bypass must not touch
  tunnel traffic.

## Capabilities and Constraints

- Tabs: Overview (state, reachability per service), Strategies (Flowseal,
  Zapret 2 NEXT presets, own), Lists (user hostlists/ipsets, upstream lists),
  Search (autopick, blockcheck2), Engine (update, doctor, logs, removal),
  Settings (autostart, IPv6, game filter, ipset mode, Discord voice).
- Privileged steps (setup, engine update, system copy update, removal) ask for
  a password via polkit; everything else is passwordless.
- x86_64 only (release binary). blockcheck2 needs `host`/`nslookup` (bind).
- A strategy that helps one ISP can break sites on another: the product must
  make that visible (baseline comparison) rather than hide it.

## Brand Commitments

Name "Zapret2". UI copy in Russian. Credits to bol-van (zapret2), Flowseal
and Zapret 2 NEXT stay visible in the README.

## Evidence on Hand

Real measurements from the author's network (2026-10). That network already
runs zapret on the router, so these numbers only show which strategies break
nothing, not DPI-bypass efficacy: without bypass 12/14; all 22 translated
Flowseal strategies 11-12/14; NEXT tcp_md5 presets drop to 2-4/14. Efficacy
against real ISP DPI is untested so far.
No users, testimonials or download numbers exist yet; do not invent them.

## Product Principles

1. On and forgotten: the default path is install, autopick, done.
2. Never make things worse silently: show the no-bypass baseline and what each
   strategy breaks.
3. Track upstream: Flowseal strategies and lists come from the source, not
   from a frozen copy.
4. Root sees only code it owns; user input is data.
5. Feel like part of Omarchy, not an app bolted onto it.
