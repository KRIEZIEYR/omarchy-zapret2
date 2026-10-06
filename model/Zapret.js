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
  if (n.indexOf("next-") === 0) return niceTitle(n.substring(5)) + " · Z2"
  if (n.indexOf("my-") === 0) return n.substring(3)
  return niceTitle(n) + " · Z2"
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
// HTTP/3 (QUIC) probes are ignored everywhere: a category passes when all
// non-http3 probes pass, and counts only cover non-http3 probes.
function categories(check) {
  var cats = check && check.categories ? check.categories : {}
  var order = ["youtube", "discord", "google", "cloudflare"]
  var outList = []
  for (var k in cats) if (order.indexOf(k) === -1) order.push(k)
  for (var i = 0; i < order.length; i++) {
    var c = cats[order[i]]
    if (!c) continue
    if (c && Array.isArray(c.results)) {
      var probes = c.results.filter(function(r) { return !r.http3 })
      var okFiltered = probes.filter(function(r) { return r.ok }).length
      var totalFiltered = probes.length
      if (totalFiltered === 0) {
        outList.push({ key: order[i], label: c.label || order[i], ok: 0, total: 0, good: true })
        continue
      }
      outList.push({ key: order[i], label: c.label || order[i], ok: okFiltered, total: totalFiltered,
                     good: okFiltered === totalFiltered })
      continue
    }
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

// Map manager error output to actionable Russian text for the user.
function actionErrorText(message) {
  var s = String(message || "").toLowerCase()
  if (!s.trim()) return "Неизвестная ошибка"
  if (s.indexOf("python3") !== -1 || s.indexOf("no such file") !== -1 || s.indexOf("enoent") !== -1) {
    return "Не найден python3 — установите: omarchy pkg add python"
  }
  if (s.indexOf("not installed") !== -1 || s.indexOf("not set up") !== -1 || s.indexOf("engine not found") !== -1) {
    return "Сначала установите движок (вкладка Обзор → Установить)"
  }
  if (s.indexOf("not authorized") !== -1 || s.indexOf("cancelled") !== -1 || s.indexOf("auth canceled") !== -1 || s.indexOf("пользователь отменил") !== -1) {
    return "Отменено: пароль не введён"
  }
  if (s.indexOf("permission denied") !== -1 || s.indexOf("access denied") !== -1) {
    return "Нет прав: запустите установку (пароль)"
  }
  // Exit code fallback
  var codeMatch = s.match(/код[^\d]*(\d+)/) || s.match(/exit[^\d]*(\d+)/) || s.match(/code[^\d]*(\d+)/)
  if (codeMatch) return "Команда не выполнилась (код " + codeMatch[1] + "): откройте Движок → Журнал"
  if (s.indexOf("омархи-запрет") !== -1 || s.indexOf("omarchy-zapret") !== -1) {
    return "Команда не выполнилась: откройте Движок → Журнал"
  }
  return message
}

// Failed categories in an autopick row: categories where ok < total.
// Accepts both [ok, total] arrays and {ok, total} objects (see breaksText).
// Untested rows (no category with total > 0) count as 999 so they sort last.
function failCount(row) {
  var cats = (row && row.categories) || {}
  var keys = Object.keys(cats)
  var fails = 0
  var anyTested = false
  for (var i = 0; i < keys.length; i++) {
    var c = cats[keys[i]]
    var ok = 0, tt = 0
    if (c && typeof c === "object" && !Array.isArray(c)) { ok = c.ok | 0; tt = c.total | 0 }
    else if (Array.isArray(c)) { ok = c[0] | 0; tt = c[1] | 0 }
    if (tt > 0) { anyTested = true; if (ok < tt) fails++ }
  }
  if (!anyTested) {
    if ((row && (row.total | 0)) > 0) return ((row.score | 0) >= (row.total | 0)) ? 0 : 1
    return 999
  }
  return fails
}

// Autopick table rows sorted best first, with a percent.
// Order: fewer failed categories first, then score desc, then the chosen
// one, then the no-bypass baseline, then tested before untested, then name.
function autopickRows(ap) {
  var a = ap || {}
  var rows = a.rows ? a.rows.slice() : []
  if (a.baseline) rows.push(a.baseline)
  var chosen = a.chosen || ""
  rows.sort(function(x, y) {
    var fx = failCount(x), fy = failCount(y)
    if (fx !== fy) return fx - fy
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
             categories: r.categories !== undefined ? r.categories : {},
             error: r.error || "", chosen: chosen === r.preset, baseline: r.preset === "(off)",
             fails: failCount(r) }
  })
}

// Check context for the verdict note (never part of text).
function checkNote(check, now) {
  if (!check || !check.time) return ""
  var a = ago(check.time, now)
  return "по проверке " + (a ? a + ", " : "") + "обход был " + (check.active ? "включён" : "выключен")
}

// Short reason for failing categories: the first non-QUIC curl error;
// fallback when no host details exist. HTTP/3 probes never produce a reason.
function failReason(check, failing) {
  var cats = (check && check.categories) || {}
  var failed = []
  for (var i = 0; i < failing.length; i++) {
    var r = (cats[failing[i].key] && cats[failing[i].key].results) || []
    for (var j = 0; j < r.length; j++) if (!r[j].ok && !r[j].http3) failed.push(r[j])
  }
  if (failed.length > 0) return curlError(failed[0].error)
  return "не открываются"
}

// Overview verdict: pure, null-safe. Actions: "none" | "on" | "autopick" | "check".
var NOT_NEEDED_TEXT = "Всё открывается"
// Why a baseline that already passes needs no bypass. Shared by Overview and
// Strategies so the two tabs cannot drift into contradicting each other.
var NOT_NEEDED_EXPL = "Сайты открываются и так."
var CHECK_EXPLAINER = "11 проверок = адреса YouTube, Discord, Google, Cloudflare по TLS. QUIC-пробы не учитываются."
function failedHosts(check) {
  var cats = (check && check.categories) || {}
  var out = []
  for (var k in cats) {
    var rs = (cats[k] && cats[k].results) || []
    for (var i = 0; i < rs.length; i++) if (!rs[i].ok && !rs[i].http3) out.push(rs[i])
  }
  return out
}
function hasFailing(check) {
  var cats = categories(check)
  for (var i = 0; i < cats.length; i++) if (!cats[i].good) return true
  return false
}
function hasError(check) {
  return hasFailing(check)
}
function validHosts(text) {
  var parts = String(text || "").split(/[\s,;]+/)
  var valid = 0, total = 0
  for (var i = 0; i < parts.length; i++) {
    var cut = String(parts[i]).trim().toLowerCase()
    if (!cut) continue
    while (cut.charAt(0) === "^" || cut.charAt(0) === "*" || cut.charAt(0) === ".") cut = cut.substring(1)
    while (cut.length > 0 && cut.charAt(cut.length - 1) === ".") cut = cut.substring(0, cut.length - 1)
    if (!cut) continue
    total++
    if (isValidDomain(cut)) valid++
  }
  return { valid: valid, total: total, dropped: total - valid }
}
function verdict(st, check, autopick, now) {
  if (check !== null && check !== undefined && typeof check === "object" && check.preset !== undefined) {
    var curPreset = (st && st.settings) ? String(st.settings.preset || "") : ""
    var curOn = (stateOf(st) === "on" || stateOf(st) === "starting")
    var presetMismatch = check.preset !== undefined && String(check.preset) !== curPreset
    var activeMismatch = check.active !== undefined && (!!check.active) !== curOn
    if (presetMismatch || activeMismatch) {
      var checked = (check.preset !== undefined && check.preset !== null && String(check.preset) !== "")
          ? String(check.preset) : curPreset
      var checkedTitle = presetTitle(checked) || checked || "—"
      var curTitle = presetTitle(curPreset) || "—"
      // The one place that knows a check belongs to another configuration.
      // Spelled out with both sides, so the warning has a referent instead of
      // an unexplained "для другой стратегии".
      return { text: "", tone: "neutral", action: "check",
               note: "Последняя проверка была для " + checkedTitle + " (обход "
                   + (check.active ? "вкл" : "выкл") + ") — сейчас " + curTitle
                   + " (обход " + (curOn ? "вкл" : "выкл") + ")" }
    }
  }
  var s = stateOf(st)
  var on = (s === "on" || s === "starting")
  var ap = autopick || {}
  var hasPick = !!(ap && ap.time)
  var notNeeded = !!(ap && ap.notNeeded)
  var cats = categories(check)
  var failing = cats.filter(function(c) { return !c.good })
  var note = checkNote(check, now)
  if (cats.length === 0) {
    if (!on && notNeeded) return { text: NOT_NEEDED_TEXT, tone: "neutral", action: "none", note: note }
    if (!on && !hasPick) return { text: "Запустите автоподбор, чтобы найти рабочую стратегию", tone: "neutral", action: "autopick", note: note }
    return { text: "Проверок ещё не было", tone: "neutral", action: "none", note: note }
  }
  if (failing.length === 0) {
    if (!on) return { text: NOT_NEEDED_TEXT, tone: "neutral", action: "none", note: note }
    return { text: "Всё открывается", tone: "good", action: "none", note: note }
  }
  // Any category below full: the bypass may still help, never "не нужен".
  var names = failing.map(function(c) { return c.label }).join("/")
  var partial = failing.some(function(c) { return c.ok > 0 })
  return { text: names + (partial ? " частично" : "") + ": " + failReason(check, failing),
           tone: "error", action: "autopick", note: note }
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

// Popup dropdown label: "General · 12/14 · лучшая", plus
// "⚠ хуже, чем без обхода" when worse than the no-bypass baseline.
// A tied row shows nothing extra (never "лучшая").
// Score part is omitted when score/total is missing or total <= 0.
function presetLabel(name, score, total, isBest, worseThanBaseline, tied) {
  if (name && typeof name === "object") {
    var row = name
    var presetName = row.preset !== undefined ? row.preset : row.name
    var rowBest = row.chosen === true || row.isBest === true || row.best === true
    var rowTied = row.tied === true || row.isTied === true
    var explicitBest = (typeof score === "boolean") ? score : rowBest
    var explicitWorse = (typeof score === "boolean") ? total
      : (typeof total === "boolean" ? total : row.worseThanBaseline)
    var explicitTied = (typeof score === "boolean" && typeof total === "boolean") ? worseThanBaseline
      : (typeof total === "boolean" && typeof isBest === "boolean") ? isBest
      : (typeof tied === "boolean") ? tied : rowTied
    if (typeof score !== "boolean" && typeof total !== "boolean" && typeof isBest !== "boolean"
        && typeof worseThanBaseline !== "boolean" && typeof tied !== "boolean") {
      explicitTied = rowTied
    }
    return presetLabel(presetName, row.score, row.total, explicitBest, explicitWorse, explicitTied)
  }
  if (score && typeof score === "object") {
    var obj = score
    // Called as presetLabel(name, {score, total}, isBest, worse, tied):
    // total holds isBest, isBest holds worse, worseThanBaseline holds tied.
    return presetLabel(name, obj.score, obj.total, total, isBest, worseThanBaseline)
  }
  if (typeof total === "boolean") {
    // Shorthand presetLabel(name, score, isBest, worse, tied).
    return presetLabel(name, score, undefined, total, isBest, worseThanBaseline)
  }
  var title = presetTitle(name)
  var parts = []
  if (title) parts.push(title)
  else if (name) parts.push(String(name))
  var sc = Number(score), tt = Number(total)
  if (score !== null && score !== undefined && total !== null && total !== undefined
      && !isNaN(sc) && !isNaN(tt) && tt > 0) {
    parts.push((sc | 0) + "/" + (tt | 0))
  }
  if (isBest && !tied) parts.push("лучшая")
  if (worseThanBaseline) parts.push("⚠ хуже, чем без обхода")
  return parts.join(" · ")
}

var TEST_TITLES = { curl_test_http: "HTTP", curl_test_https_tls12: "TLS 1.2", curl_test_https_tls13: "TLS 1.3",
                    curl_test_http3: "QUIC" }

function findingTitle(f) {
  return (TEST_TITLES[f.test] || f.test) + " · " + f.domain + " · " + f.ip
}

// Relative luminance of a hex color (0..1, WCAG). Accepts "#rgb" or "#rrggbb".
function luminance(hex) {
  var s = String(hex || "").replace(/^#/, "")
  if (/^[0-9a-fA-F]{3}$/.test(s))
    s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
  if (!/^[0-9a-fA-F]{6}$/.test(s)) return 0
  var r = parseInt(s.substr(0, 2), 16) / 255
  var g = parseInt(s.substr(2, 2), 16) / 255
  var b = parseInt(s.substr(4, 2), 16) / 255
  function lin(c) { return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

// WCAG contrast ratio of two hex colors: (L1 + 0.05) / (L2 + 0.05).
function contrastRatio(a, b) {
  var l1 = luminance(a), l2 = luminance(b)
  if (l1 < l2) { var t = l1; l1 = l2; l2 = t }
  return (l1 + 0.05) / (l2 + 0.05)
}

// Urgent color kept only when readable on the background, else the fallback.
function pickBad(urgent, bg, fallback) {
  var fb = fallback || "#e06c75"
  return contrastRatio(urgent, bg) >= 3 ? urgent : fb
}

// Mix two colors, t = 0 keeps `a`, t = 1 gives `b`. Secondary text is built by
// mixing toward the background instead of darkening the foreground: Qt.darker
// only ever darkens, so it collapses on a light theme. Returns "#rrggbb", which
// QML accepts anywhere a color is expected. QML color channels are 0..1.
function mixColor(a, b, t) {
  var k = Math.max(0, Math.min(1, Number(t) || 0))
  var ch = function(p) {
    var x = Number(a && a[p])
    var y = Number(b && b[p])
    if (isNaN(x) || isNaN(y)) return 0
    return Math.round((x * (1 - k) + y * k) * 255)
  }
  var hex = function(v) {
    var s = Math.max(0, Math.min(255, v)).toString(16)
    return s.length < 2 ? "0" + s : s
  }
  return "#" + hex(ch("r")) + hex(ch("g")) + hex(ch("b"))
}

// Split search rows into the no-bypass baseline and the ranked rest:
// baseline (flagged baseline/isBaseline/"(off)", else the first row),
// best (single max-score row, first on tie), ties (same score as best),
// rest (everything else). Empty input gives nulls and empty lists.
function groupSearchRows(rows) {
  var list = Array.isArray(rows) ? rows.slice() : []
  if (list.length === 0) return { baseline: null, best: null, ties: [], rest: [] }
  var bi = -1, i
  for (i = 0; i < list.length; i++) {
    var fl = list[i] || {}
    if (fl.baseline || fl.isBaseline || fl.preset === "(off)") { bi = i; break }
  }
  var baseline = bi !== -1 ? list.splice(bi, 1)[0] : list.shift()
  if (list.length === 0) return { baseline: baseline, best: null, ties: [], rest: [] }
  function scoreOf(r) { var n = Number(r && r.score); return isNaN(n) ? 0 : n }
  var max = scoreOf(list[0])
  for (i = 1; i < list.length; i++) if (scoreOf(list[i]) > max) max = scoreOf(list[i])
  var best = null, ties = [], rest = []
  for (i = 0; i < list.length; i++) {
    if (scoreOf(list[i]) !== max) { rest.push(list[i]); continue }
    if (best === null) best = list[i]; else ties.push(list[i])
  }
  return { baseline: baseline, best: best, ties: ties, rest: rest }
}

// Localise a doctor item detail to Russian; unknown details pass through.
function doctorDetail(name, detail) {
  var s = detail === null || detail === undefined ? "" : String(detail)
  if (!s) return s
  s = s.split("inactive (dead)").join("остановлена")
  s = s.split("inactive").join("остановлена")
  s = s.split("active (running)").join("работает")
  s = s.split("bundled").join("встроенные")
  s = s.split("presets").join("пресетов")
  s = s.split("restarts").join("перезапусков")
  s = s.split("the plugin was updated: run setup --app-only (Update system part)").join("плагин обновлён: установите обновление системной части")
  s = s.split("blockcheck2 needs them: omarchy pkg add bind").join("нужны для blockcheck2: omarchy pkg add bind")
  s = s.replace(/^omarchy-xray TUN is on:.*$/, "включён TUN omarchy-xray: трафик идёт в туннель, обход не применяется")
  s = s.replace(/(\d+)\s*files? intact/g, "$1 файлов в порядке")
  s = s.split("install nftables/curl/polkit").join("установите nftables/curl/polkit")
  s = s.replace(/install (.+)/g, "установите $1")
  s = s.split("for blockcheck2").join("для blockcheck2")
  s = s.split("run setup").join("запустите установку")
  return s
}

// Human label for a blockcheck progress line; unknown lines pass through.
function blockcheckPhase(line) {
  var s = line === null || line === undefined ? "" : String(line)
  if (!s) return ""
  if (s === "checking system") return "Проверка системы"
  if (s === "checking already running DPI bypass processes") return "Проверка других обходов"
  if (s === "checking privileges") return "Проверка прав"
  if (s === "checking prerequisites") return "Проверка зависимостей"
  if (s.indexOf("curl_test") !== -1) return "Перебор стратегий…"
  if (s.indexOf("SUMMARY") !== -1) return "Готово"
  return s
}

// Short per-row verdict for autopick rows: which categories still fail.
// When something fails, passing categories are marked with ✓, e.g.
// "YouTube ✗ · Discord ✓". All-open rows say "всё открывается".
function breaksText(row) {
  if (!row) return "не проверялась"
  var cats = row.categories || {}
  var keys = Object.keys(cats)
  var totals = 0
  var i
  for (i = 0; i < keys.length; i++) {
    var v = cats[keys[i]]
    var t = 0
    if (v && typeof v === "object" && !Array.isArray(v)) t = v.total | 0
    else if (Array.isArray(v)) t = v[1] | 0
    if (t > 0) { totals += t; break }
  }
  var total = row.total | 0
  var score = row.score | 0
  var hasTested = total > 0 || totals > 0
  if (!hasTested) {
    if (row.error) return String(row.error)
    return "не проверялась"
  }
  if (total > 0 && score >= total) return "всё открывается"
  var labels = { youtube: "YouTube", discord: "Discord", google: "Google", cloudflare: "Cloudflare" }
  var parts = []
  var hasFail = false
  for (i = 0; i < keys.length; i++) {
    var k = keys[i]
    var c = cats[k]
    var ok = 0, tt = 0
    if (c && typeof c === "object" && !Array.isArray(c)) { ok = c.ok | 0; tt = c.total | 0 }
    else if (Array.isArray(c)) { ok = c[0] | 0; tt = c[1] | 0 }
    if (!(tt > 0)) continue
    var label = labels.hasOwnProperty(k) ? labels[k] : k
    if (ok < tt) {
      hasFail = true
      parts.push(label + " ✗")
    } else {
      parts.push(label + " ✓")
    }
  }
  if (hasFail) return parts.join(" · ")
  if (total > 0 && score < total) return "не проверялась"
  return "всё открывается"
}

// "2026-10-05T23:09:53+03:00 host proc[1]: msg" -> "23:09:53 msg".
// Journal short format ("Oct 05 23:09:53 host proc[1]: msg") works too;
// anything else passes through unchanged.
function shortLog(line) {
  var s = line === null || line === undefined ? "" : String(line)
  if (!s) return s
  var m = s.match(/^(?:\d{4}-\d{2}-\d{2}T)?(\d{2}:\d{2}:\d{2})(?:\.\d+)?(?:Z|[\+\-]\d{2}:?\d{2})?\s+(?:\S+\s+)?(?:\S+\[\d+\]:\s+)?(.*)$/)
  if (m) return m[1] + " " + m[2]
  var j = s.match(/^[A-Z][a-z]{2}\s+\d{1,2}\s+(\d{2}:\d{2}:\d{2})\s+(?:\S+\s+)?(?:\S+\[\d+\]:\s+)?(.*)$/)
  if (j) return j[1] + " " + j[2]
  return s
}

// Lines of a list editor: trimmed, without blanks.
function countLines(text) {
  return String(text || "").split("\n").filter(function(l) { return l.trim() !== "" && l.trim().charAt(0) !== "#" }).length
}

// Unified stale wording for app and popup: "устарело · 2 ч назад"
// when the check is stale, otherwise just "2 ч назад" / "только что".
// Returns "" when there is no check time.
function staleLabel(check, isStale, now) {
  if (!check || !check.time) return ""
  var a = ago(check.time, now)
  if (!a) return ""
  return (isStale ? "устарело · " : "") + a
}

// Age and severity of the last check. The preset/state mismatch is NOT decided
// here: verdict() owns it and spells it out in its note, so one predicate, one
// wording. `st` is gone from the signature for that reason.
// Returns { text: "", severity: "none" | "error" }; "error" = older than 6h
// while something is still failing.
function staleStatus(check, now) {
  if (!check || !check.time) return { text: "", severity: "none" }
  var ageSec = Math.max(0, Math.round((now || Date.now() / 1000) - Number(check.time)))
  var old = ageSec > 6 * 3600
  return { text: staleLabel(check, old, now), severity: (old && hasFailing(check)) ? "error" : "none" }
}

// Severity for a doctor row: "ok" when passing, otherwise
// "action" (needs a password step now), "optional" (expected / info only),
// or "error" (real failure). host/nslookup (bind) and VPN-tunnel notes are
// optional info; a plugin/system-copy mismatch needs action.
function doctorSeverity(name, ok, detail) {
  if (ok) return "ok"
  var n = String(name || "")
  var d = String(detail || "")
  if (n === "host/nslookup" || n.indexOf("host") !== -1 && n.indexOf("nslookup") !== -1) return "optional"
  if (d.indexOf("bind") !== -1) return "optional"
  if (n === "No VPN tunnel") return "optional"
  if (n === "Plugin and system copy") return "action"
  if (d.indexOf("плагин обновлён") !== -1 || d.indexOf("setup --app-only") !== -1) return "action"
  return "error"
}

// True when a log line is worth showing in the "только важное" mode:
// errors, failures, warnings, found strategies and exits.
function importantLog(line) {
  var s = String(line || "").toLowerCase()
  if (!s.trim()) return false
  if (s.indexOf("error") !== -1) return true
  if (s.indexOf("fail") !== -1) return true
  if (s.indexOf("warn") !== -1) return true
  if (s.indexOf("ошиб") !== -1) return true
  if (s.indexOf("strategy") !== -1) return true
  if (s.indexOf("стратег") !== -1) return true
  if (s.indexOf("working") !== -1) return true
  if (s.indexOf("found") !== -1) return true
  if (s.indexOf("available") !== -1) return true
  if (s.indexOf("exit") !== -1) return true
  if (s.indexOf("!!!!!") !== -1) return true
  if (s.charAt(0) === "*" || s.trim().charAt(0) === "*") return true
  return false
}

var DOMAIN_RE = /^(?=.{1,253}$)([a-z0-9_]([a-z0-9_-]{0,61}[a-z0-9_])?\.)*[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/

function isValidDomain(d) {
  return DOMAIN_RE.test(String(d || ""))
}

// Split free text (spaces, commas, semicolons) into plain hostnames for
// `check <domain…>`: lowercase, stripped, deduped. Anything that is not a
// plain hostname lands in `invalid` (shown back to the user as typed).
function parseDomains(text) {
  var parts = String(text || "").split(/[\s,;]+/)
  var domains = [], invalid = [], seen = {}
  for (var i = 0; i < parts.length; i++) {
    var raw = String(parts[i]).trim()
    if (!raw) continue
    var cut = raw.toLowerCase().replace(/\.+$/, "")
    if (!cut || cut.length > 253 || cut.indexOf("/") !== -1 || cut.indexOf(":") !== -1 || !isValidDomain(cut)) {
      invalid.push(raw)
      continue
    }
    if (!seen[cut]) { seen[cut] = true; domains.push(cut) }
  }
  return { domains: domains, invalid: invalid }
}

function isValidIPv4(s) {
  var parts = String(s || "").split(".")
  if (parts.length !== 4) return false
  for (var i = 0; i < 4; i++) {
    if (!/^\d{1,3}$/.test(parts[i])) return false
    var n = Number(parts[i])
    if (n < 0 || n > 255) return false
  }
  return true
}

function isValidIPv6(s) {
  var addr = String(s || "")
  if (addr.indexOf(":") === -1) return false
  if (!/^[0-9a-fA-F:.]+$/.test(addr)) return false
  if (addr.indexOf(":::") !== -1) return false
  var halves = addr.split("::")
  if (halves.length > 2) return false
  function checkSide(side) {
    if (side === "") return 0
    var groups = side.split(":")
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (g.indexOf(".") !== -1) {
        if (!isValidIPv4(g)) return -1
      } else {
        if (!/^[0-9a-fA-F]{1,4}$/.test(g)) return -1
      }
    }
    return groups.length
  }
  if (halves.length === 1) {
    var n = checkSide(addr)
    return n > 0 && n <= 8
  }
  var left = checkSide(halves[0])
  var right = checkSide(halves[1])
  if (left < 0 || right < 0) return false
  return (left + right) <= 7
}

function isValidIPNetwork(s) {
  var str = String(s || "")
  var slash = str.split("/")
  if (slash.length > 2) return false
  var addr = slash[0]
  var isV6 = addr.indexOf(":") !== -1
  if (slash.length === 2) {
    if (!/^\d{1,3}$/.test(slash[1])) return false
    var plen = Number(slash[1])
    if (isV6) { if (plen < 0 || plen > 128) return false }
    else { if (plen < 0 || plen > 32) return false }
  }
  return isV6 ? isValidIPv6(addr) : isValidIPv4(addr)
}

// Backup size caps mirror the manager (MAX_BACKUP_TOTAL/MAX_BACKUP_FILE).
var MAX_BACKUP_TOTAL = 2 * 1024 * 1024
var MAX_BACKUP_FILE = 512 * 1024

function isValidBackupSize(size) {
  var n = Number(size)
  return n > 0 && n <= MAX_BACKUP_TOTAL
}

function isValidBackupFileSize(size) {
  var n = Number(size)
  return n >= 0 && n <= MAX_BACKUP_FILE
}

// Daily update check summary (engine, lists, presets). Pure, null-safe.
function updateCheckText(info) {
  var r = info || {}
  var e = r.engine || {}
  var parts = []
  if (e.latest) parts.push(e.update ? "Движок: есть " + e.latest : "Движок актуален")
  else if (e.error) parts.push("Движок: не проверен")
  else parts.push("Движок: не проверен")
  parts.push(r.listsStale ? "списки устарели" : "списки свежие")
  parts.push(r.presetsStale ? "стратегии устарели" : "стратегии свежие")
  return parts.join(" · ")
}

// Live valid/dropped counts mirroring the manager clean_list rules:
// domains with optional ^ prefix (host lists) or IP/CIDR (ipset lists).
// Blank and comment-only lines are ignored (neither valid nor dropped).
// Returns {valid, dropped}.
function validLines(text, kind) {
  var valid = 0, dropped = 0
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var cut = String(lines[i]).split("#", 1)[0].trim()
    if (!cut) continue
    var low = cut.toLowerCase()
    if (kind === "ipset") {
      if (isValidIPNetwork(low)) valid++
      else dropped++
    } else {
      var d = low
      while (d.charAt(0) === "^") d = d.substring(1)
      while (d.charAt(0) === "*" || d.charAt(0) === ".") d = d.substring(1)
      while (d.length > 0 && d.charAt(d.length - 1) === ".") d = d.substring(0, d.length - 1)
      if (d && isValidDomain(d)) valid++
      else dropped++
    }
  }
  return { valid: valid, dropped: dropped }
}
