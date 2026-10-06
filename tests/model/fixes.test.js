test("failCount prefers fewer broken categories", () => {
  const a = { preset: "a", score: 8, total: 14, categories: { youtube: [0, 6], discord: [4, 4], google: [2, 2], cloudflare: [2, 2] } }
  const b = { preset: "b", score: 12, total: 14, categories: { youtube: [5, 6], discord: [3, 4], google: [2, 2], cloudflare: [2, 2] } }
  eq(Model.failCount(a), 1)
  eq(Model.failCount(b), 2)
  const rows = Model.autopickRows({ chosen: "none", rows: [b, a] })
  eq(rows.map(r => r.preset), ["a", "b"])
})

test("failCount same score tie-break", () => {
  const a = { preset: "a", score: 5, total: 10, categories: { youtube: [0, 5], discord: [5, 5] } }
  const b = { preset: "b", score: 5, total: 10, categories: { youtube: [3, 5], discord: [2, 5] } }
  const rows = Model.autopickRows({ chosen: "none", rows: [b, a] })
  eq(rows.map(r => r.preset), ["a", "b"])
})

test("presetLabel tied shows = без обхода", () => {
  eq(Model.presetLabel("fs-general", 12, 14, true, false, true), "General · 12/14 · = без обхода")
  eq(Model.presetLabel("fs-general", 12, 14, false, false, true), "General · 12/14 · = без обхода")
  eq(Model.presetLabel("fs-general", 12, 14, true, false, false), "General · 12/14 · лучшая")
  eq(Model.presetLabel({ preset: "fs-general", score: 12, total: 14, chosen: true, tied: true }), "General · 12/14 · = без обхода")
})

test("staleLabel unified wording", () => {
  eq(Model.staleLabel(null, false), "")
  eq(Model.staleLabel({}, true), "")
  eq(Model.staleLabel({ time: 1000 }, true, 1000 + 7200), "устарело · 2 ч назад")
  eq(Model.staleLabel({ time: 1000 }, false, 1000 + 7200), "2 ч назад")
  eq(Model.staleLabel({ time: 1000 }, false, 1030), "только что")
})

test("staleStatus reports age only; the mismatch lives in verdict()", () => {
  const now = 100000
  const fresh = { time: now - 7200, preset: "alt5", active: true }
  // No check
  eq(Model.staleStatus(null, now), { text: "", severity: "none" })
  eq(Model.staleStatus({}, now), { text: "", severity: "none" })
  // Fresh check: age, never a mismatch verdict
  eq(Model.staleStatus(fresh, now), { text: "2 ч назад", severity: "none" })
  eq(Model.staleStatus(Object.assign({}, fresh, { preset: "general" }), now), { text: "2 ч назад", severity: "none" })
  eq(Model.staleStatus(Object.assign({}, fresh, { active: false }), now), { text: "2 ч назад", severity: "none" })
  // Old (>6h) with failing categories -> error
  const oldCheck = { time: now - 32400, preset: "general", active: true, categories: { youtube: { label: "YouTube", ok: 0, total: 3 } } }
  eq(Model.staleStatus(oldCheck, now), { text: "устарело · 9 ч назад", severity: "error" })
  // Old but nothing failing -> no error
  const oldCheckOk = { time: now - 32400, preset: "general", active: true, categories: { youtube: { label: "YouTube", ok: 3, total: 3 } } }
  eq(Model.staleStatus(oldCheckOk, now), { text: "устарело · 9 ч назад", severity: "none" })
  // Not old but failing -> not an error, the failures are in the verdict
  const recentFailing = { time: now - 7200, preset: "general", active: true, categories: { youtube: { label: "YouTube", ok: 0, total: 3 } } }
  eq(Model.staleStatus(recentFailing, now), { text: "2 ч назад", severity: "none" })
})

test("mixColor moves toward the background in both themes", () => {
  const white = { r: 255, g: 255, b: 255 }
  const black = { r: 0, g: 0, b: 0 }
  eq(Model.mixColor(white, black, 0), "#ffffff")
  eq(Model.mixColor(white, black, 1), "#000000")
  eq(Model.mixColor(white, black, 0.5), "#808080")
  // Same call on a dark theme: toward the background, never darker than bg.
  eq(Model.mixColor(white, black, 0.34), "#a8a8a8")
  eq(Model.mixColor({}, black, 0.5), "#000000")
})

test("validLines host lists", () => {
  eq(Model.validLines("example.com\nsub.example.org\n# comment\n\nbad host\n", "host"), { valid: 2, dropped: 1 })
  eq(Model.validLines("YouTube.com\n*.googlevideo.com\n^dns.google\n^^x\n", "host"), { valid: 4, dropped: 0 })
  eq(Model.validLines("example.org. # tail\n../etc\n", "host"), { valid: 1, dropped: 1 })
})

test("validLines ipset lists", () => {
  eq(Model.validLines("1.2.3.0/24\n1.2.3.4\n2001:db8::/32\nnope\n300.1.1.1\n", "ipset"), { valid: 3, dropped: 2 })
  eq(Model.validLines("# only comment\n\n", "ipset"), { valid: 0, dropped: 0 })
})

test("doctorSeverity three levels", () => {
  eq(Model.doctorSeverity("Setup", true, ""), "ok")
  eq(Model.doctorSeverity("Setup", false, "missing"), "error")
  eq(Model.doctorSeverity("host/nslookup", false, "нужны для blockcheck2: omarchy pkg add bind"), "optional")
  eq(Model.doctorSeverity("No VPN tunnel", false, "включён TUN omarchy-xray"), "optional")
  eq(Model.doctorSeverity("Plugin and system copy", false, "плагин обновлён: установите обновление системной части"), "action")
})

test("importantLog filters noise", () => {
  eq(Model.importantLog("23:16:49 binding this socket to queue '220'"), false)
  eq(Model.importantLog("23:16:49 loading plain text list"), false)
  eq(Model.importantLog("!!!!! curl_test_https_tls12: working strategy found"), true)
  eq(Model.importantLog("* checking prerequisites"), true)
  eq(Model.importantLog("connection failed: reset"), true)
  eq(Model.importantLog("WARN: something odd"), true)
  eq(Model.importantLog("exit 1: nfqws died"), true)
  eq(Model.importantLog(""), false)
})
