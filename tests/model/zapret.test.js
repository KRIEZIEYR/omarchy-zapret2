test("preset titles", () => {
  eq(Model.presetTitle("general"), "NEXT · General")
  eq(Model.presetTitle("alt"), "NEXT · ALT")
  eq(Model.presetTitle("alt5"), "NEXT · ALT 5")
  eq(Model.presetTitle("alt11"), "NEXT · ALT 11")
  eq(Model.presetTitle("fake-tls-auto"), "NEXT · Fake TLS Auto")
  eq(Model.presetTitle("fake-tls-auto-alt2"), "NEXT · Fake TLS Auto ALT 2")
  eq(Model.presetTitle("simple-fake"), "NEXT · Simple Fake")
  eq(Model.presetTitle("voice"), "NEXT · Voice")
  eq(Model.presetTitle("custom-safe"), "NEXT · Custom Safe")
  eq(Model.presetTitle("custom-balanced"), "NEXT · Custom Balanced")
  eq(Model.presetTitle("custom-aggressive"), "NEXT · Custom Aggressive")
  eq(Model.presetTitle("my-home"), "home")
  eq(Model.presetTitle(undefined), "")
  eq(Model.presetTitle(""), "")
  eq(Model.presetTitle("(off)"), "Без обхода")
  eq(Model.presetTitle("fs-general"), "General")
  eq(Model.presetTitle("fs-general-alt2"), "ALT 2")
  eq(Model.presetTitle("fs-general-fake-tls-auto-alt2"), "Fake TLS Auto ALT 2")
  eq(Model.presetTitle("fs-general-simple-fake"), "Simple Fake")
  eq(Model.presetTitle("fs-general-exp"), "EXP")
  eq(Model.presetTitle("fs-alt11"), "ALT 11")
})

test("group titles", () => {
  eq(Model.groupTitle("flowseal"), "Flowseal")
  eq(Model.groupTitle("next"), "Zapret 2 NEXT")
  eq(Model.groupTitle("custom"), "Свои")
})

test("doctor names", () => {
  eq(Model.doctorName("Setup"), "Установка")
  eq(Model.doctorName("System files"), "Системные файлы")
  eq(Model.doctorName("Plugin and system copy"), "Плагин и системная копия")
  eq(Model.doctorName("nfqws2"), "nfqws2")
  eq(Model.doctorName("nft"), "nft")
  eq(Model.doctorName("curl"), "curl")
  eq(Model.doctorName("pkexec"), "pkexec")
  eq(Model.doctorName("host/nslookup"), "host/nslookup")
  eq(Model.doctorName("No other zapret"), "Нет других zapret")
  eq(Model.doctorName("No VPN tunnel"), "Нет VPN-туннеля")
  eq(Model.doctorName("Flowseal presets"), "Пресеты Flowseal")
  eq(Model.doctorName("Service"), "Служба")
  eq(Model.doctorName("unknown item"), "unknown item")
  eq(Model.doctorName(undefined), "")
})

test("state", () => {
  eq(Model.stateOf(null), "unknown")
  eq(Model.stateOf({ installed: false }), "setup")
  eq(Model.stateOf({ installed: true, active: "active" }), "on")
  eq(Model.stateOf({ installed: true, active: "inactive" }), "off")
  eq(Model.stateOf({ installed: true, active: "failed" }), "error")
  eq(Model.stateOf({ installed: true, active: "activating", restarts: 2 }), "error")
  eq(Model.stateOf({ installed: true, active: "activating", restarts: 0 }), "starting")
  eq(Model.summary({ installed: true, active: "active", settings: { preset: "alt5" } }), "Zapret2 · Включён · NEXT · ALT 5")
  eq(Model.summary({ installed: true, active: "active", settings: { preset: "fs-general-alt2" } }), "Zapret2 · Включён · Flowseal ALT 2")
  eq(Model.summary({ installed: true, active: "active", settings: { preset: "fs-general" } }), "Zapret2 · Включён · Flowseal General")
})

test("categories keep a stable order", () => {
  const check = { categories: { google: { label: "Google", ok: 2, total: 2 }, youtube: { label: "YouTube", ok: 1, total: 3 }, extra: { ok: 0, total: 1 } } }
  eq(Model.categories(check).map(c => c.key), ["youtube", "google", "extra"])
  eq(Model.categories(check)[1].good, true)
  eq(Model.checkLine(check), "YouTube 1/3 · Google 2/2 · extra 0/1")
  eq(Model.checkLine({}), "Проверок ещё не было")
})

test("json lines", () => {
  eq(Model.lastJson('{"progress":true,"step":1}\n{"ok":true}\n'), { ok: true })
  eq(Model.lastJson("garbage"), null)
  eq(Model.parseLine('{"a":1}'), { a: 1 })
  eq(Model.parseLine("noise"), null)
})

test("autopick rows", () => {
  const rows = Model.autopickRows({ chosen: "alt", rows: [{ preset: "general", score: 3, total: 11 }, { preset: "alt", score: 11, total: 11 }, { preset: "alt3", score: -1, total: 0, error: "x" }] })
  eq(rows.map(r => r.preset), ["alt", "general", "alt3"])
  eq(rows[0].pct, 100)
  eq(rows[0].chosen, true)
  eq(rows[2].pct, 0)
})

test("misc", () => {
  eq(Model.ago(1000, 1030), "только что")
  eq(Model.ago(1000, 1000 + 7200), "2 ч назад")
  eq(Model.ago(0, 5), "")
  eq(Model.findingTitle({ test: "curl_test_http3", domain: "youtube.com", ip: "ipv4" }), "QUIC · youtube.com · ipv4")
  eq(Model.countLines("a\n\n# c\nb\n"), 2)
})

test("autopick tie-break: name asc, untested last", () => {
  const byName = Model.autopickRows({ chosen: "none", rows: [{ preset: "voice", score: 5, total: 10 }, { preset: "general", score: 5, total: 10 }, { preset: "alt", score: 5, total: 10 }] })
  eq(byName.map(r => r.preset), ["alt", "general", "voice"])
  const testedFirst = Model.autopickRows({ chosen: "none", rows: [{ preset: "b", score: 0, total: 0 }, { preset: "a", score: 0, total: 10 }] })
  eq(testedFirst.map(r => r.preset), ["a", "b"])
  eq(Model.autopickRows(null), [])
  eq(Model.autopickRows(undefined), [])
})

test("verdict", () => {
  const NOT_NEEDED = "Обход здесь не нужен: сайты открываются и так (возможно, роутер или VPN уже обходят блокировки)"
  const on = { installed: true, active: "active" }
  const off = { installed: true, active: "inactive" }
  const allOk = { categories: { youtube: { label: "YouTube", ok: 3, total: 3 }, google: { label: "Google", ok: 2, total: 2 } } }
  const someFail = { categories: { youtube: { label: "YouTube", ok: 0, total: 3 }, discord: { label: "Discord", ok: 1, total: 2 }, google: { label: "Google", ok: 2, total: 2 } } }
  const picked = { time: 1000, chosen: "alt", notNeeded: false, rows: [] }
  const notNeeded = { time: 1000, chosen: "(off)", notNeeded: true, rows: [] }

  eq(Model.verdict(on, allOk, picked), { text: "Всё открывается", tone: "good", action: "none", note: "" })
  eq(Model.verdict(off, allOk, notNeeded), { text: NOT_NEEDED, tone: "neutral", action: "none", note: "" })
  eq(Model.verdict(off, someFail, picked), { text: "YouTube/Discord частично: не открываются", tone: "warn", action: "autopick", note: "" })
  eq(Model.verdict(on, someFail, picked).tone, "warn")
  eq(Model.verdict(on, someFail, picked).action, "autopick")
  eq(Model.verdict(off, someFail, null).action, "autopick")
  eq(Model.verdict(off, someFail, {}).action, "autopick")
  eq(Model.verdict(off, {}, null), { text: "Запустите автоподбор, чтобы найти рабочую стратегию", tone: "neutral", action: "autopick", note: "" })
  eq(Model.verdict(off, null, notNeeded), { text: NOT_NEEDED, tone: "neutral", action: "none", note: "" })
  eq(Model.verdict(null, null, null).action, "autopick")
  eq(Model.verdict(on, {}, picked), { text: "Проверок ещё не было", tone: "neutral", action: "none", note: "" })
  // Fresh check with bypass off and every category full means no bypass needed,
  // even without an autopick result.
  eq(Model.verdict(off, allOk, null), { text: NOT_NEEDED, tone: "neutral", action: "none", note: "" })
  eq(Model.verdict(off, allOk, picked), { text: NOT_NEEDED, tone: "neutral", action: "none", note: "" })
})

test("verdict partial never says not needed", () => {
  const off = { installed: true, active: "inactive" }
  const partial = { categories: { youtube: { label: "YouTube", ok: 2, total: 3 }, google: { label: "Google", ok: 2, total: 2 } } }
  const notNeeded = { time: 1000, chosen: "(off)", notNeeded: true, rows: [] }
  const v = Model.verdict(off, partial, notNeeded)
  eq(v.tone, "warn")
  eq(v.action, "autopick")
  if (v.text.indexOf("не нужен") !== -1) throw new Error("partial must not say not needed: " + v.text)
  if (v.text.indexOf("частично") === -1) throw new Error("partial text must say частично: " + v.text)
})

test("verdict QUIC-only failure", () => {
  const off = { installed: true, active: "inactive" }
  const quicOnly = { categories: { youtube: { label: "YouTube", ok: 1, total: 2, results: [
    { url: "https://youtube.com", ok: true, http3: false, error: "" },
    { url: "https://youtube.com", ok: false, http3: true, error: "(28) timeout" },
  ] } } }
  const v = Model.verdict(off, quicOnly, null)
  eq(v, { text: "YouTube частично: может грузиться медленно (QUIC) — попробуйте другую стратегию", tone: "warn", action: "autopick", note: "" })
})

test("verdict note carries check context", () => {
  const off = { installed: true, active: "inactive" }
  const allOk = { categories: { youtube: { label: "YouTube", ok: 3, total: 3 } } }
  const wasOff = Object.assign({ time: 1000, active: false }, allOk)
  const wasOn = Object.assign({ time: 1000, active: true }, allOk)
  eq(Model.verdict(off, wasOff, null, 1000 + 300).note, "по проверке 5 мин назад, обход был выключен")
  eq(Model.verdict(off, wasOn, null, 1000 + 300).note, "по проверке 5 мин назад, обход был включён")
  eq(Model.verdict(off, wasOff, null, 1000 + 10).note, "по проверке только что, обход был выключен")
})

test("curlError", () => {
  eq(Model.curlError("curl: (28) Operation timed out after 6000 milliseconds"), "таймаут")
  eq(Model.curlError("curl: (35) OpenSSL SSL_connect: Connection reset by peer"), "ошибка TLS (DPI?)")
  eq(Model.curlError("curl: (6) Could not resolve host: youtube.com"), "DNS не отвечает")
  eq(Model.curlError("curl: (7) Failed to connect: Connection refused"), "соединение отклонено")
  eq(Model.curlError("curl: (56) Recv failure: Connection reset by peer"), "соединение сброшено")
  eq(Model.curlError("curl exit 7"), "ошибка")
  eq(Model.curlError(null), "ошибка")
  eq(Model.curlError(""), "ошибка")
  eq(Model.curlError(undefined), "ошибка")
})

test("popupPresets", () => {
  const presets = [{ name: "general" }, { name: "alt" }, { name: "alt3" }, { name: "alt5" }, { name: "voice" }, { name: "custom-balanced" }, { name: "simple-fake" }]
  const ap = { time: 1, chosen: "alt5", rows: [{ preset: "alt5", score: 10, total: 10 }, { preset: "alt", score: 9, total: 10 }, { preset: "general", score: 8, total: 10 }, { preset: "voice", score: 7, total: 10 }, { preset: "alt3", score: 6, total: 10 }, { preset: "simple-fake", score: 5, total: 10 }], baseline: { preset: "(off)", score: 2, total: 10 } }
  eq(Model.popupPresets(presets, ap, "general"), ["general", "alt5", "alt", "voice", "alt3"])
  // deduped: active already in top5 is not repeated
  eq(Model.popupPresets(presets, ap, "alt5"), ["alt5", "alt", "general", "voice", "alt3"])
  // fallback to first 5 when there are no autopick rows
  eq(Model.popupPresets(presets, null, "voice"), ["voice", "general", "alt", "alt3", "alt5"])
  eq(Model.popupPresets(presets, {}, null), ["general", "alt", "alt3", "alt5", "voice"])
  eq(Model.popupPresets(null, null, null), [])
})
test("autopick baseline row", () => {
  const rows = Model.autopickRows({ chosen: "alt5", baseline: { preset: "(off)", score: 12, total: 14 }, rows: [{ preset: "alt5", score: 12, total: 14 }, { preset: "general", score: 1, total: 14 }] })
  eq(rows.map(r => r.title), ["NEXT · ALT 5", "Без обхода", "NEXT · General"])
  const tie = Model.autopickRows({ chosen: "alt", baseline: { preset: "(off)", score: 11, total: 14 }, rows: [{ preset: "voice", score: 11, total: 14 }, { preset: "alt", score: 11, total: 14 }] })
  eq(tie.map(r => r.preset), ["alt", "(off)", "voice"])
  eq(rows[1].baseline, true)
  eq(rows[1].chosen, false)
})

test("verdict stale check", () => {
  const on = { installed: true, active: "active", settings: { preset: "alt5" } }
  const off = { installed: true, active: "inactive", settings: { preset: "alt5" } }
  const cats = { youtube: { label: "YouTube", ok: 3, total: 3 }, google: { label: "Google", ok: 2, total: 2 } }
  const fresh = { time: 1000, preset: "alt5", active: true, categories: cats }
  eq(Model.verdict(on, Object.assign({}, fresh, { preset: "general" }), null),
    { text: "", tone: "neutral", action: "check", note: "Проверка устарела: стратегия general, обход был включён" })
  eq(Model.verdict(on, Object.assign({}, fresh, { active: false }), null),
    { text: "", tone: "neutral", action: "check", note: "Проверка устарела: стратегия alt5, обход был выключен" })
  eq(Model.verdict(off, Object.assign({}, fresh, { preset: "alt5", active: false, categories: cats }), null).text, "Обход здесь не нужен: сайты открываются и так (возможно, роутер или VPN уже обходят блокировки)")
  eq(Model.verdict(on, fresh, null, 1010), { text: "Всё открывается", tone: "good", action: "none", note: "по проверке только что, обход был включён" })
  eq(Model.verdict(on, null, null), { text: "Проверок ещё не было", tone: "neutral", action: "none", note: "" })
})

test("luminance and contrast", () => {
  const near = (a, b, d) => { if (Math.abs(a - b) > d) throw new Error(a + " not ≈ " + b) }
  near(Model.luminance("#000000"), 0, 0.001)
  near(Model.luminance("#ffffff"), 1, 0.001)
  near(Model.luminance("#fff"), 1, 0.001)
  near(Model.luminance("000"), 0, 0.001)
  near(Model.contrastRatio("#000000", "#ffffff"), 21, 0.01)
  near(Model.contrastRatio("#ffffff", "#000000"), 21, 0.01)
  eq(Model.pickBad("#ffffff", "#000000"), "#ffffff")
  eq(Model.pickBad("#e06c75", "#e06c75"), "#e06c75")
  eq(Model.pickBad("#777777", "#888888", "#123456"), "#123456")
})

test("groupSearchRows", () => {
  eq(Model.groupSearchRows([]), { baseline: null, best: null, ties: [], rest: [] })
  eq(Model.groupSearchRows(null), { baseline: null, best: null, ties: [], rest: [] })
  eq(Model.groupSearchRows(undefined), { baseline: null, best: null, ties: [], rest: [] })
  const rows = [
    { preset: "(off)", score: 2, total: 10, baseline: true },
    { preset: "general", score: 8, total: 10 },
    { preset: "alt", score: 10, total: 10 },
    { preset: "voice", score: 10, total: 10 },
    { preset: "alt3", score: 5, total: 10 },
  ]
  const g = Model.groupSearchRows(rows)
  eq(g.baseline.preset, "(off)")
  eq(g.best.preset, "alt")
  eq(g.ties.map(r => r.preset), ["voice"])
  eq(g.rest.map(r => r.preset), ["general", "alt3"])
  const flagged = Model.groupSearchRows([{ preset: "a", score: 1, isBaseline: true }, { preset: "b", score: 5 }, { preset: "c", score: 3 }])
  eq(flagged.baseline.preset, "a")
  eq(flagged.best.preset, "b")
  eq(flagged.rest.map(r => r.preset), ["c"])
  const noFlag = Model.groupSearchRows([{ preset: "a", score: 1 }, { preset: "b", score: 2 }])
  eq(noFlag.baseline.preset, "a")
  eq(noFlag.best.preset, "b")
  eq(noFlag.ties, [])
  eq(noFlag.rest, [])
  const onlyBase = Model.groupSearchRows([{ preset: "(off)", score: 2, baseline: true }])
  eq(onlyBase.baseline.preset, "(off)")
  eq(onlyBase.best, null)
})

test("doctorDetail", () => {
  eq(Model.doctorDetail("Setup", "run setup"), "запустите установку")
  eq(Model.doctorDetail("Plugin and system copy", "the plugin was updated: run setup --app-only (Update system part)"), "плагин обновлён: установите обновление системной части")
  eq(Model.doctorDetail("host/nslookup", "blockcheck2 needs them: omarchy pkg add bind"), "нужны для blockcheck2: omarchy pkg add bind")
  eq(Model.doctorDetail("host/nslookup", "for blockcheck2"), "для blockcheck2")
  eq(Model.doctorDetail("System files", "142 files intact"), "142 файлов в порядке")
  eq(Model.doctorDetail("System files", "1 file intact"), "1 файлов в порядке")
  eq(Model.doctorDetail("No VPN tunnel", "omarchy-xray TUN is on: traffic leaves through the tunnel, the bypass does not apply"), "включён TUN omarchy-xray: трафик идёт в туннель, обход не применяется")
  eq(Model.doctorDetail("nft", "install nftables/curl/polkit"), "установите nftables/curl/polkit")
  eq(Model.doctorDetail("nft", "install nftables"), "установите nftables")
  eq(Model.doctorDetail("curl", "install curl"), "установите curl")
  eq(Model.doctorDetail("pkexec", "install polkit"), "установите polkit")
  eq(Model.doctorDetail("Setup", "another user"), "another user")
  eq(Model.doctorDetail("Setup", "please run setup now"), "please запустите установку now")
})

test("shortLog", () => {
  eq(Model.shortLog("2026-10-05T23:09:53+03:00 thinkbook systemd[1]: msg"), "23:09:53 msg")
  eq(Model.shortLog("23:09:53 thinkbook systemd[1]: hello world"), "23:09:53 hello world")
  eq(Model.shortLog("Oct 05 23:09:53 thinkbook systemd[1]: hi"), "23:09:53 hi")
  eq(Model.shortLog("plain line without time"), "plain line without time")
})

test("autopick rows keep categories", () => {
  const rows = Model.autopickRows({ chosen: "alt", rows: [{ preset: "alt", score: 5, total: 10, categories: { youtube: [1, 3] } }] })
  eq(rows[0].categories, { youtube: [1, 3] })
  const nocat = Model.autopickRows({ rows: [{ preset: "general", score: 1, total: 2 }] })
  eq(nocat[0].categories, {})
})

test("breaksText", () => {
  eq(Model.breaksText({ score: 10, total: 10, categories: { youtube: [3, 3] } }), "всё открывается")
  eq(Model.breaksText({ score: 1, total: 3, categories: { youtube: [1, 3] } }), "YouTube ✗ QUIC")
  eq(Model.breaksText({ score: 0, total: 3, categories: { youtube: [0, 3] } }), "YouTube ✗")
  eq(Model.breaksText({ score: 1, total: 5, categories: { youtube: [0, 3], discord: [1, 2] } }), "YouTube ✗ · Discord ✗")
  eq(Model.breaksText({ score: 0, total: 0, categories: {} }), "не проверялась")
  eq(Model.breaksText(null), "не проверялась")
  eq(Model.breaksText({ score: 0, total: 0, categories: {}, error: "boom" }), "boom")
  eq(Model.breaksText({ score: 1, total: 3, categories: { youtube: { ok: 1, total: 3, label: "YouTube" } } }), "YouTube ✗ QUIC")
  eq(Model.breaksText({ score: 3, total: 3, categories: { google: { ok: 2, total: 2 } } }), "всё открывается")
  eq(Model.breaksText({ score: 0, total: 2, categories: { custom: { ok: 0, total: 2 } } }), "custom ✗")
})

test("blockcheckPhase", () => {
  eq(Model.blockcheckPhase("checking system"), "Проверка системы")
  eq(Model.blockcheckPhase("checking already running DPI bypass processes"), "Проверка других обходов")
  eq(Model.blockcheckPhase("checking privileges"), "Проверка прав")
  eq(Model.blockcheckPhase("checking prerequisites"), "Проверка зависимостей")
  eq(Model.blockcheckPhase("curl_test_http youtube.com"), "Перебор стратегий…")
  eq(Model.blockcheckPhase("SUMMARY done"), "Готово")
  eq(Model.blockcheckPhase("some other line"), "some other line")
  eq(Model.blockcheckPhase(null), "")
  eq(Model.blockcheckPhase(undefined), "")
})

test("doctorDetail additions", () => {
  eq(Model.doctorDetail("Service", "inactive (dead)"), "остановлена")
  eq(Model.doctorDetail("Service", "inactive"), "остановлена")
  eq(Model.doctorDetail("Service", "active (running)"), "работает")
  eq(Model.doctorDetail("Flowseal presets", "bundled presets"), "встроенные пресетов")
  eq(Model.doctorDetail("Service", "3 restarts"), "3 перезапусков")
})

test("verdict neutral not-needed text", () => {
  const NOT_NEEDED = "Обход здесь не нужен: сайты открываются и так (возможно, роутер или VPN уже обходят блокировки)"
  const off = { installed: true, active: "inactive" }
  const on = { installed: true, active: "active" }
  const allOk = { categories: { youtube: { label: "YouTube", ok: 3, total: 3 }, google: { label: "Google", ok: 2, total: 2 } } }
  const notNeeded = { time: 1000, chosen: "(off)", notNeeded: true, rows: [] }
  const v1 = Model.verdict(off, allOk, notNeeded)
  eq(v1, { text: NOT_NEEDED, tone: "neutral", action: "none", note: "" })
  const v2 = Model.verdict(off, allOk, null)
  eq(v2.text, NOT_NEEDED)
  eq(v2.tone, "neutral")
  eq(v2.action, "none")
  // Bypass on with everything open stays good, never neutral.
  eq(Model.verdict(on, allOk, notNeeded).tone, "good")
})

test("breaksText mixed pass and fail", () => {
  eq(Model.breaksText({ score: 3, total: 5, categories: { youtube: [1, 3], discord: [2, 2] } }), "YouTube ✗ QUIC · Discord ✓")
  eq(Model.breaksText({ score: 2, total: 5, categories: { youtube: { ok: 0, total: 3 }, discord: { ok: 2, total: 2 } } }), "YouTube ✗ · Discord ✓")
  eq(Model.breaksText({ score: 5, total: 5, categories: { youtube: [3, 3], discord: [2, 2] } }), "всё открывается")
})

test("presetLabel", () => {
  eq(Model.presetLabel("fs-general", 12, 14, true, false), "General · 12/14 · лучшая")
  eq(Model.presetLabel("fs-general", 8, 14, false, true), "General · 8/14 · ⚠ хуже, чем без обхода")
  eq(Model.presetLabel("fs-general", 8, 14, false, false), "General · 8/14")
  // Missing score degrades gracefully.
  eq(Model.presetLabel("fs-general", null, 0, false, false), "General")
  eq(Model.presetLabel("fs-general", undefined, undefined, true, false), "General · лучшая")
  eq(Model.presetLabel("fs-general"), "General")
  eq(Model.presetLabel("(off)", 14, 14, true, false), "Без обхода · 14/14 · лучшая")
  // Shorthand (name, score, isBest, worse) without total.
  eq(Model.presetLabel("fs-general", 12, true, false), "General · лучшая")
  // Row-object forms.
  eq(Model.presetLabel({ preset: "fs-general", score: 12, total: 14, chosen: true }), "General · 12/14 · лучшая")
  eq(Model.presetLabel({ preset: "fs-general", score: 12, total: 14 }, true, false), "General · 12/14 · лучшая")
  eq(Model.presetLabel("fs-general", { score: 12, total: 14 }, true, false), "General · 12/14 · лучшая")
})
