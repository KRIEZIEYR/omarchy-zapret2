test("update badge", () => {
  eq(Model.updateBadgeLabel({}), "Проверка обновлений ещё не выполнялась")
  eq(Model.updateBadgeLabel({ checked: 0 }), "Проверка обновлений ещё не выполнялась")
  eq(Model.updateBadgeLabel({ checked: 1000, engine: false, lists: false, presets: false }, 1030),
    "Обновлений нет · проверено только что")
  eq(Model.updateBadgeLabel({ checked: 1, engine: true, latest: "v2" }), "Есть обновления: движок v2")
  eq(Model.updateBadgeLabel({ checked: 1, engine: true }), "Есть обновления: движок")
  eq(Model.updateBadgeLabel({ checked: 1, lists: true, presets: true }), "Есть обновления: списки, стратегии")
})

test("serviceTitle", () => {
  eq(Model.serviceTitle("telegram"), "Telegram")
  eq(Model.serviceTitle("whatsapp"), "WhatsApp")
  eq(Model.serviceTitle("unknown-xyz"), "unknown-xyz")
})

test("firstRunStep", () => {
  eq(Model.firstRunStep(null, null), 1)
  eq(Model.firstRunStep({ installed: false }, {}), 1)
  eq(Model.firstRunStep({ installed: true }, {}), 2)
  eq(Model.firstRunStep({ installed: true }, { time: 5 }), 3)
})

test("updateBadgeLabel", () => {
  eq(Model.updateBadgeLabel({ engine: true, lists: false, presets: true, latest: "v2" }),
    "Есть обновления: движок v2, стратегии")
  eq(Model.updateBadgeLabel({ engine: false, lists: false, presets: false, checked: 1000 }, 1000 + 7200),
    "Обновлений нет · проверено 2 ч назад")
  eq(Model.updateBadgeLabel({}), "Проверка обновлений ещё не выполнялась")
})

test("dnsStatusText", () => {
  eq(Model.dnsStatusText({ dns: ["1.1.1.1", "8.8.8.8"] }), "DNS: 1.1.1.1, 8.8.8.8")
  eq(Model.dnsStatusText({}), "DNS-серверы не определены")
})
