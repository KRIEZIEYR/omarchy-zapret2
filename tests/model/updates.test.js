test("update badge", () => {
  eq(Model.updateBadgeLabel({}), "Проверка обновлений ещё не выполнялась")
  eq(Model.updateBadgeLabel({ checked: 0 }), "Проверка обновлений ещё не выполнялась")
  eq(Model.updateBadgeLabel({ checked: 1000, engine: false, lists: false, presets: false }, 1030),
    "Обновлений нет · проверено только что")
  eq(Model.updateBadgeLabel({ checked: 1, engine: true, latest: "v2" }), "Есть обновления: движок v2")
  eq(Model.updateBadgeLabel({ checked: 1, engine: true }), "Есть обновления: движок")
  eq(Model.updateBadgeLabel({ checked: 1, lists: true, presets: true }), "Есть обновления: списки, стратегии")
})

test("redactIps", () => {
  eq(Model.redactIps("a 1.2.3.4 b"), "a [IP] b")
  eq(Model.redactIps("x 2001:db8::1 y").indexOf("::1"), -1)
  eq(Model.redactIps("go https://youtube.com/x y"), "go [URL] y")
  eq(Model.redactIps("open youtube.com now"), "open [host] now")
  eq(Model.redactIps("Oct 06 10:00:00 h ok"), "Oct 06 10:00:00 h ok")
})

test("suggestImportName", () => {
  eq(Model.suggestImportName("~/my-strategy.txt"), "my-strategy")
  eq(Model.suggestImportName("https://example.com/General ALT.txt?x=1"), "general-alt")
  eq(Model.suggestImportName(""), "imported")
})
