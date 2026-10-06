test("updateCheckText", () => {
  eq(Model.updateCheckText({ engine: { latest: "v2", update: true }, listsStale: false, presetsStale: true }),
    "Движок: есть v2 · списки свежие · стратегии устарели")
  eq(Model.updateCheckText({ engine: { latest: "v1", update: false }, listsStale: false, presetsStale: false }),
    "Движок актуален · списки свежие · стратегии свежие")
  eq(Model.updateCheckText({}), "Движок: не проверен · списки свежие · стратегии свежие")
})
