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
