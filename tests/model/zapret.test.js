test("preset titles", () => {
  eq(Model.presetTitle("general"), "General")
  eq(Model.presetTitle("alt"), "ALT")
  eq(Model.presetTitle("alt5"), "ALT 5")
  eq(Model.presetTitle("fake-tls-auto"), "Fake TLS Auto")
  eq(Model.presetTitle("fake-tls-auto-alt2"), "Fake TLS Auto ALT 2")
  eq(Model.presetTitle("simple-fake"), "Simple Fake")
  eq(Model.presetTitle("voice"), "Voice")
  eq(Model.presetTitle("custom-safe"), "Custom Safe")
  eq(Model.presetTitle("custom-balanced"), "Custom Balanced")
  eq(Model.presetTitle("custom-aggressive"), "Custom Aggressive")
  eq(Model.presetTitle("my-home"), "home")
  eq(Model.presetTitle(undefined), "")
  eq(Model.presetTitle("(off)"), "Без обхода")
  eq(Model.presetTitle("fs-general"), "General")
  eq(Model.presetTitle("fs-general-alt2"), "ALT 2")
  eq(Model.presetTitle("fs-general-fake-tls-auto-alt2"), "Fake TLS Auto ALT 2")
  eq(Model.presetTitle("fs-general-simple-fake"), "Simple Fake")
  eq(Model.presetTitle("fs-general-exp"), "EXP")
})

test("group titles", () => {
  eq(Model.groupTitle("flowseal"), "Flowseal")
  eq(Model.groupTitle("next"), "Zapret 2 NEXT")
  eq(Model.groupTitle("custom"), "Свои")
})

test("state", () => {
  eq(Model.stateOf(null), "unknown")
  eq(Model.stateOf({ installed: false }), "setup")
  eq(Model.stateOf({ installed: true, active: "active" }), "on")
  eq(Model.stateOf({ installed: true, active: "inactive" }), "off")
  eq(Model.stateOf({ installed: true, active: "failed" }), "error")
  eq(Model.stateOf({ installed: true, active: "activating", restarts: 2 }), "error")
  eq(Model.stateOf({ installed: true, active: "activating", restarts: 0 }), "starting")
  eq(Model.summary({ installed: true, active: "active", settings: { preset: "alt5" } }), "Zapret2 · Включён · ALT 5")
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
  const on = { installed: true, active: "active" }
  const off = { installed: true, active: "inactive" }
  const allOk = { categories: { youtube: { label: "YouTube", ok: 3, total: 3 }, google: { label: "Google", ok: 2, total: 2 } } }
  const someFail = { categories: { youtube: { label: "YouTube", ok: 0, total: 3 }, discord: { label: "Discord", ok: 1, total: 2 }, google: { label: "Google", ok: 2, total: 2 } } }
  const picked = { time: 1000, chosen: "alt", notNeeded: false, rows: [] }
  const notNeeded = { time: 1000, chosen: "(off)", notNeeded: true, rows: [] }

  eq(Model.verdict(on, allOk, picked), { text: "Всё открывается", tone: "good", action: "none" })
  eq(Model.verdict(off, allOk, notNeeded), { text: "В этой сети обход сейчас не нужен", tone: "neutral", action: "none" })
  eq(Model.verdict(off, someFail, picked), { text: "YouTube/Discord не открываются — включите обход", tone: "bad", action: "on" })
  eq(Model.verdict(on, someFail, picked).tone, "warn")
  eq(Model.verdict(on, someFail, picked).action, "none")
  eq(Model.verdict(off, someFail, null).action, "autopick")
  eq(Model.verdict(off, someFail, {}).action, "autopick")
  eq(Model.verdict(off, {}, null), { text: "Запустите автоподбор, чтобы найти рабочую стратегию", tone: "neutral", action: "autopick" })
  eq(Model.verdict(off, null, notNeeded), { text: "В этой сети обход сейчас не нужен", tone: "neutral", action: "none" })
  eq(Model.verdict(null, null, null).action, "autopick")
  eq(Model.verdict(on, {}, picked), { text: "Проверок ещё не было", tone: "neutral", action: "none" })
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
  eq(rows.map(r => r.title), ["ALT 5", "Без обхода", "General"])
  const tie = Model.autopickRows({ chosen: "alt", baseline: { preset: "(off)", score: 11, total: 14 }, rows: [{ preset: "voice", score: 11, total: 14 }, { preset: "alt", score: 11, total: 14 }] })
  eq(tie.map(r => r.preset), ["alt", "(off)", "voice"])
  eq(rows[1].baseline, true)
  eq(rows[1].chosen, false)
})
