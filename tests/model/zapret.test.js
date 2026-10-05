test("preset titles", () => {
  eq(Model.presetTitle("fake-tls-auto-alt2"), "FAKE TLS AUTO ALT2")
  eq(Model.presetTitle("my-home"), "home")
  eq(Model.presetTitle(undefined), "")
})

test("state", () => {
  eq(Model.stateOf(null), "unknown")
  eq(Model.stateOf({ installed: false }), "setup")
  eq(Model.stateOf({ installed: true, active: "active" }), "on")
  eq(Model.stateOf({ installed: true, active: "inactive" }), "off")
  eq(Model.stateOf({ installed: true, active: "failed" }), "error")
  eq(Model.stateOf({ installed: true, active: "activating", restarts: 2 }), "error")
  eq(Model.stateOf({ installed: true, active: "activating", restarts: 0 }), "starting")
  eq(Model.summary({ installed: true, active: "active", settings: { preset: "alt5" } }), "Zapret2 · Включён · ALT5")
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

test("autopick baseline row", () => {
  const rows = Model.autopickRows({ chosen: "alt5", baseline: { preset: "(off)", score: 12, total: 14 }, rows: [{ preset: "alt5", score: 12, total: 14 }, { preset: "general", score: 1, total: 14 }] })
  eq(rows.map(r => r.title), ["ALT5", "Без обхода", "General"])
  const tie = Model.autopickRows({ chosen: "alt", baseline: { preset: "(off)", score: 11, total: 14 }, rows: [{ preset: "voice", score: 11, total: 14 }, { preset: "alt", score: 11, total: 14 }] })
  eq(tie.map(r => r.preset), ["alt", "(off)", "voice"])
  eq(rows[1].baseline, true)
  eq(rows[1].chosen, false)
})
