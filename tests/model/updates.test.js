test("update badge", () => {
  eq(Model.updateBadgeLabel({}), "Проверка обновлений ещё не выполнялась")
  eq(Model.updateBadgeLabel({ checked: 0 }), "Проверка обновлений ещё не выполнялась")
  eq(Model.updateBadgeLabel({ checked: 1000, engine: false, lists: false, presets: false }, 1030),
    "Обновлений нет · проверено только что")
  eq(Model.updateBadgeLabel({ checked: 1, engine: true, latest: "v2" }), "Есть обновления: движок v2")
  eq(Model.updateBadgeLabel({ checked: 1, engine: true }), "Есть обновления: движок")
  eq(Model.updateBadgeLabel({ checked: 1, lists: true, presets: true }), "Есть обновления: списки, стратегии")
})
