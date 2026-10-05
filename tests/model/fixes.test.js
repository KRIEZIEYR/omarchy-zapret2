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

test("validLines host lists", () => {
  eq(Model.validLines("example.com\nsub.example.org\n# comment\n\nbad host\n", "host"), { valid: 2, dropped: 1 })
  eq(Model.validLines("YouTube.com\n*.googlevideo.com\n^dns.google\n^^x\n", "host"), { valid: 4, dropped: 0 })
  eq(Model.validLines("example.org. # tail\n../etc\n", "host"), { valid: 1, dropped: 1 })
})

test("validLines ipset lists", () => {
  eq(Model.validLines("1.2.3.0/24\n1.2.3.4\n2001:db8::/32\nnope\n300.1.1.1\n", "ipset"), { valid: 3, dropped: 2 })
  eq(Model.validLines("# only comment\n\n", "ipset"), { valid: 0, dropped: 0 })
})
