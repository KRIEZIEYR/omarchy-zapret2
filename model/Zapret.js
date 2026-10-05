.pragma library

// Pure helpers shared by Service.qml, BarWidget.qml and App.qml; tested in
// node by tests/run.js (no QML here).

function titleWord(w) {
  var s = String(w || "")
  if (!s) return ""
  var m = s.match(/^alt(\d*)$/i)
  if (m) return m[1] ? "ALT " + m[1] : "ALT"
  var low = s.toLowerCase()
  if (low === "exp") return "EXP"
  if (low === "tls") return "TLS"
  return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase()
}

function niceTitle(stem) {
  return String(stem || "").split("-").filter(function(p) { return p !== "" }).map(titleWord).join(" ")
}

function presetTitle(name) {
  var n = String(name || "")
  if (!n) return ""
  if (n === "(off)") return "Без обхода"
  if (n === "fs-general") return "General"
  if (n.indexOf("fs-general-") === 0) return niceTitle(n.substring("fs-general-".length))
  if (n.indexOf("fs-") === 0) return niceTitle(n.substring(3))
  if (n.indexOf("my-") === 0) return n.substring(3)
  return "NEXT · " + niceTitle(n)
}

function groupTitle(g) {
  var n = String(g || "")
  if (n === "flowseal") return "Flowseal"
  if (n === "next") return "Zapret 2 NEXT"
  if (n === "custom") return "Свои"
  return n
}

var DOCTOR_NAMES = { "Setup": "Установка", "System files": "Системные файлы",
                     "Plugin and system copy": "Плагин и системная копия",
                     "No other zapret": "Нет других zapret", "No VPN tunnel": "Нет VPN-туннеля",
                     "Flowseal presets": "Пресеты Flowseal", "Service": "Служба" }

function doctorName(name) {
  var n = String(name || "")
  return DOCTOR_NAMES.hasOwnProperty(n) ? DOCTOR_NAMES[n] : n
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
  var raw = st.settings ? String(st.settings.preset || "") : ""
  var preset = raw ? presetTitle(raw) : ""
  if (preset && raw.indexOf("fs-") === 0) preset = "Flowseal " + preset
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
  var a = ap || {}
  var rows = a.rows ? a.rows.slice() : []
  if (a.baseline) rows.push(a.baseline)
  var chosen = a.chosen || ""
  // score desc, then the chosen one, then the no-bypass baseline,
  // then tested before untested, then name asc.
  rows.sort(function(x, y) {
    var d = (y.score | 0) - (x.score | 0)
    if (d) return d
    var cx = x.preset === chosen ? 0 : 1, cy = y.preset === chosen ? 0 : 1
    if (cx !== cy) return cx - cy
    var bx = x.preset === "(off)" ? 0 : 1, by = y.preset === "(off)" ? 0 : 1
    if (bx !== by) return bx - by
    var tx = (x.total | 0) > 0 ? 0 : 1, ty = (y.total | 0) > 0 ? 0 : 1
    if (tx !== ty) return tx - ty
    var nx = String(x.preset || ""), ny = String(y.preset || "")
    return nx < ny ? -1 : nx > ny ? 1 : 0
  })
  return rows.map(function(r) {
    return { preset: r.preset, title: presetTitle(r.preset), score: r.score, total: r.total,
             pct: r.total > 0 ? Math.round(100 * Math.max(0, r.score) / r.total) : 0,
             error: r.error || "", chosen: chosen === r.preset, baseline: r.preset === "(off)" }
  })
}

// Check context for the verdict note (never part of text).
function checkNote(check, now) {
  if (!check || !check.time) return ""
  var a = ago(check.time, now)
  return "по проверке " + (a ? a + ", " : "") + "обход был " + (check.active ? "включён" : "выключен")
}

// Short reason for failing categories: "QUIC" when only http3 probes fail,
// otherwise the first curl error; fallback when no host details exist.
function failReason(check, failing) {
  var cats = (check && check.categories) || {}
  var failed = []
  for (var i = 0; i < failing.length; i++) {
    var r = (cats[failing[i].key] && cats[failing[i].key].results) || []
    for (var j = 0; j < r.length; j++) if (!r[j].ok) failed.push(r[j])
  }
  if (failed.length > 0 && failed.every(function(h) { return h.http3 })) return "QUIC не проходит"
  if (failed.length > 0) return curlError(failed[0].error)
  return "не открываются"
}

// Overview verdict: pure, null-safe. Actions: "none" | "on" | "autopick".
function verdict(st, check, autopick, now) {
  var s = stateOf(st)
  var on = (s === "on" || s === "starting")
  var ap = autopick || {}
  var hasPick = !!(ap && ap.time)
  var notNeeded = !!(ap && ap.notNeeded)
  var cats = categories(check)
  var failing = cats.filter(function(c) { return !c.good })
  var note = checkNote(check, now)
  if (cats.length === 0) {
    if (!on && notNeeded) return { text: "Сайты открываются и без обхода (возможно, обход уже работает на роутере или в VPN)", tone: "neutral", action: "none", note: note }
    if (!on && !hasPick) return { text: "Запустите автоподбор, чтобы найти рабочую стратегию", tone: "neutral", action: "autopick", note: note }
    return { text: "Проверок ещё не было", tone: "neutral", action: "none", note: note }
  }
  if (failing.length === 0) {
    if (!on && notNeeded) return { text: "Сайты открываются и без обхода (возможно, обход уже работает на роутере или в VPN)", tone: "neutral", action: "none", note: note }
    return { text: "Всё открывается", tone: "good", action: "none", note: note }
  }
  // Any category below full: the bypass may still help, never "не нужен".
  var names = failing.map(function(c) { return c.label }).join("/")
  var partial = failing.some(function(c) { return c.ok > 0 })
  return { text: names + (partial ? " частично" : "") + ": " + failReason(check, failing),
           tone: "warn", action: "autopick", note: note }
}

// Short human label for a curl probe error line.
function curlError(err) {
  var s = String(err || "")
  if (!s.trim()) return "ошибка"
  var l = s.toLowerCase()
  if (s.indexOf("(28)") !== -1 || l.indexOf("timed out") !== -1 || l.indexOf("timeout") !== -1 || l.indexOf("timed-out") !== -1) return "таймаут"
  if (s.indexOf("(35)") !== -1 || l.indexOf("tls") !== -1 || l.indexOf("ssl") !== -1) return "ошибка TLS (DPI?)"
  if (s.indexOf("(6)") !== -1 || l.indexOf("resolve") !== -1) return "DNS не отвечает"
  if (s.indexOf("(7)") !== -1 || l.indexOf("refused") !== -1) return "соединение отклонено"
  if (s.indexOf("(56)") !== -1 || l.indexOf("reset") !== -1) return "соединение сброшено"
  return "ошибка"
}

// Bar popup strategy list: the active one first, then the autopick top 5,
// deduped. Falls back to the first 5 presets when there are no autopick rows.
function popupPresets(presets, autopick, active) {
  var names = ((presets || []).map(function(p) {
    return typeof p === "string" ? p : (p && p.name)
  }).filter(function(n) { return !!n }))
  var top = autopickRows(autopick).filter(function(r) {
    return !r.baseline && (r.total | 0) > 0
  }).slice(0, 5).map(function(r) { return r.preset })
  if (top.length === 0) top = names.slice(0, 5)
  var out = []
  function push(n) { if (n && out.indexOf(n) === -1) out.push(n) }
  push(active)
  top.forEach(push)
  return out.slice(0, 6)
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
