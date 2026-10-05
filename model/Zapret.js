.pragma library

// Pure helpers shared by Service.qml, BarWidget.qml and App.qml; tested in
// node by tests/run.js (no QML here).

var PRESET_TITLES = {
  "general": "General", "alt": "ALT", "alt3": "ALT3", "alt5": "ALT5", "alt11": "ALT11", "alt12": "ALT12",
  "fake-tls-auto": "FAKE TLS AUTO", "fake-tls-auto-alt2": "FAKE TLS AUTO ALT2", "simple-fake": "SIMPLE FAKE",
  "voice": "VOICE", "custom-safe": "CUSTOM SAFE", "custom-balanced": "CUSTOM BALANCED",
  "custom-aggressive": "CUSTOM AGGRESSIVE"
}

function presetTitle(name) {
  var n = String(name || "")
  if (n === "(off)") return "Без обхода"
  if (PRESET_TITLES[n]) return PRESET_TITLES[n]
  return n.indexOf("my-") === 0 ? n.substring(3) : n
}

// "on" | "off" | "starting" | "error" | "setup" | "unknown"
function stateOf(st) {
  if (!st) return "unknown"
  if (!st.installed) return "setup"
  if (st.active === "failed" || (st.active === "activating" && st.restarts > 0)) return "error"
  if (st.active === "active") return "on"
  if (st.active === "activating" || st.active === "reloading") return "starting"
  return "off"
}

var STATE_TEXT = { on: "Включён", off: "Выключен", starting: "Запуск…", error: "Ошибка",
                   setup: "Не установлен", unknown: "Нет связи" }

function stateText(st) { return STATE_TEXT[stateOf(st)] }

function summary(st) {
  var s = stateOf(st)
  if (s === "setup" || s === "unknown") return "Zapret2 · " + stateText(st)
  var preset = st.settings ? presetTitle(st.settings.preset) : ""
  return "Zapret2 · " + stateText(st) + (preset ? " · " + preset : "")
}

// Check results as [{key, label, ok, total, good}] in a stable order.
function categories(check) {
  var cats = check && check.categories ? check.categories : {}
  var order = ["youtube", "discord", "google", "cloudflare"]
  var outList = []
  for (var k in cats) if (order.indexOf(k) === -1) order.push(k)
  for (var i = 0; i < order.length; i++) {
    var c = cats[order[i]]
    if (!c) continue
    outList.push({ key: order[i], label: c.label || order[i], ok: c.ok | 0, total: c.total | 0,
                   good: c.total > 0 && c.ok === c.total })
  }
  return outList
}

function checkLine(check) {
  var cs = categories(check)
  if (cs.length === 0) return "Проверок ещё не было"
  return cs.map(function(c) { return c.label + " " + c.ok + "/" + c.total }).join(" · ")
}

function ago(ts, now) {
  var t = Number(ts) || 0
  if (t <= 0) return ""
  var d = Math.max(0, Math.round((now || Date.now() / 1000) - t))
  if (d < 60) return "только что"
  if (d < 3600) return Math.round(d / 60) + " мин назад"
  if (d < 86400) return Math.round(d / 3600) + " ч назад"
  return Math.round(d / 86400) + " дн назад"
}

// Last JSON object in the text (progress lines come first), or null.
function lastJson(text) {
  var lines = String(text || "").trim().split("\n")
  for (var i = lines.length - 1; i >= 0; i--) {
    var l = lines[i].trim()
    if (l.charAt(0) !== "{") continue
    try { return JSON.parse(l) } catch (e) {}
  }
  return null
}

function parseLine(line) {
  var l = String(line || "").trim()
  if (l.charAt(0) !== "{") return null
  try { return JSON.parse(l) } catch (e) { return null }
}

// Autopick table rows sorted best first, with a percent.
function autopickRows(ap) {
  var rows = ap && ap.rows ? ap.rows.slice() : []
  if (ap && ap.baseline) rows.push(ap.baseline)
  // best first; on a tie the chosen one, then the no-bypass baseline
  function rank(r) { return r.preset === ap.chosen ? 0 : r.preset === "(off)" ? 1 : 2 }
  rows.sort(function(a, b) { return (b.score | 0) - (a.score | 0) || rank(a) - rank(b) })
  return rows.map(function(r) {
    return { preset: r.preset, title: presetTitle(r.preset), score: r.score, total: r.total,
             pct: r.total > 0 ? Math.round(100 * Math.max(0, r.score) / r.total) : 0,
             error: r.error || "", chosen: ap.chosen === r.preset, baseline: r.preset === "(off)" }
  })
}

var TEST_TITLES = { curl_test_http: "HTTP", curl_test_https_tls12: "TLS 1.2", curl_test_https_tls13: "TLS 1.3",
                    curl_test_http3: "QUIC" }

function findingTitle(f) {
  return (TEST_TITLES[f.test] || f.test) + " · " + f.domain + " · " + f.ip
}

// Lines of a list editor: trimmed, without blanks.
function countLines(text) {
  return String(text || "").split("\n").filter(function(l) { return l.trim() !== "" && l.trim().charAt(0) !== "#" }).length
}
