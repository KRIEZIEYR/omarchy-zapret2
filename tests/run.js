// node tests/run.js — runs the model tests (no dependencies).
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const src = fs.readFileSync(path.join(__dirname, "..", "model", "Zapret.js"), "utf8").replace(/^\.pragma library\s*/, "")
const Model = {}
vm.runInNewContext(src + "\nObject.assign(Model, { presetTitle, groupTitle, doctorName, stateOf, stateText, summary, categories, checkLine, ago, lastJson, parseLine, autopickRows, verdict, curlError, popupPresets, findingTitle, countLines, luminance, contrastRatio, pickBad, groupSearchRows, doctorDetail, shortLog })", { Model })

let failed = 0, passed = 0
global.test = (name, fn) => {
  try { fn(); passed++ } catch (e) { failed++; console.error("FAIL " + name + ": " + e.message) }
}
global.eq = (a, b) => {
  const x = JSON.stringify(a), y = JSON.stringify(b)
  if (x !== y) throw new Error(x + " !== " + y)
}
global.Model = Model

for (const f of fs.readdirSync(path.join(__dirname, "model"))) require(path.join(__dirname, "model", f))
console.log(passed + " passed, " + failed + " failed")
process.exit(failed ? 1 : 0)
