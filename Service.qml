import QtQuick
import Quickshell
import Quickshell.Io
import "model/Zapret.js" as Model

/*
 * Shared state for the bar widget and the app window: one instance per shell.
 * Every action is a run of bin/omarchy-zapret2 (JSON on stdout) with a
 * cleared environment; the manager talks to systemd and, once, to pkexec.
 */
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: "krieziey.omarchy-zapret2"
  readonly property string manager: decodeURIComponent(String(Qt.resolvedUrl("bin/omarchy-zapret2")).replace(/^file:\/\//, ""))

  // --- state ---------------------------------------------------------------
  property var st: null                    // last `status`
  property bool reachable: false
  readonly property string bypassState: reachable ? Model.stateOf(st) : "unknown"
  readonly property bool installed: st !== null && st.installed === true
  readonly property bool isOn: bypassState === "on" || bypassState === "starting"
  readonly property var settings: st && st.settings ? st.settings : ({})
  readonly property string preset: settings.preset || ""
  readonly property var presets: st && st.presets ? st.presets : []
  readonly property var fakeChoices: st && st.fakeChoices ? st.fakeChoices : []
  readonly property bool hostsOn: st ? st.hosts === true : false
  readonly property var check: st && st.check ? st.check : ({})
  readonly property var autopickResult: st && st.autopick ? st.autopick : ({})
  readonly property bool appCurrent: !st || st.appCurrent !== false
  readonly property string summary: reachable ? Model.summary(st) : "Zapret2 · нет связи с менеджером"

  property string lastError: ""
  readonly property string errorText: lastError !== "" ? lastError : (st && st.error ? st.error : "")
  property string flashText: ""
  property var progressInfo: null          // latest progress line of a long job
  property var blockcheck: null            // last `blockcheck status`
  readonly property bool blockcheckRunning: blockcheck !== null
      ? (blockcheck.active === "active" || blockcheck.active === "activating")
      : (st !== null && (st.blockcheck === "active" || st.blockcheck === "activating"))
  property var doctorItems: []
  property var logLines: []
  property string logNote: ""

  property bool appOpen: false
  property bool popupOpen: false
  readonly property bool watched: appOpen || popupOpen

  readonly property bool busy: _action.running || _long.running
  readonly property string busyLabel: _long.running ? _long._label : _action.running ? _action._label : ""

  property bool _autostartDone: false
  property string _lastState: ""

  // Children start with a cleared environment; null inherits that one variable.
  readonly property var baseEnv: ({
    HOME: null, USER: null, LOGNAME: null, LANG: null, PATH: null, XDG_RUNTIME_DIR: null,
    XDG_STATE_HOME: null, DBUS_SESSION_BUS_ADDRESS: null, WAYLAND_DISPLAY: null, DISPLAY: null
  })

  onBypassStateChanged: {
    if (_lastState === "on" && bypassState === "error")
      notify("Обход остановился с ошибкой. Откройте Zapret2 → Движок → Логи", true)
    _lastState = bypassState
  }

  // --- plumbing ------------------------------------------------------------
  function run(slot, args, done, label, input) {
    if (slot.running) return false
    slot._lines = []
    slot._done = done || null
    slot._label = label || ""
    slot._input = input === undefined || input === null ? "" : String(input)
    slot.environment = baseEnv
    slot.stdinEnabled = slot._input !== ""
    slot.command = [manager].concat(args)
    slot.running = true
    return true
  }

  function finish(slot, code) {
    var done = slot._done
    slot._done = null
    var text = slot._lines.join("\n")
    var data = Model.lastJson(text)
    if (data && data.progress) data = null
    var resp = { ok: data !== null && data.ok !== false && code === 0, data: data, message: "" }
    if (!resp.ok) {
      resp.message = data && data.error ? String(data.error)
          : code === 127 || code === 126 ? "Менеджер не запустился: нужен /usr/bin/python3"
          : "omarchy-zapret2 завершился с кодом " + code
    }
    if (slot === _status) reachable = data !== null
    if (done) done(resp)
    return resp
  }

  function act(args, label, okText, after, input) {
    if (busy) { flash("Подождите: " + busyLabel); return false }
    lastError = ""
    return run(_action, args, function(r) {
      if (!r.ok) lastError = Model.actionErrorText(r.message)
      else if (okText) flash(okText)
      if (after) after(r)
      refresh()
    }, label, input)
  }

  function longJob(args, label, okText, after) {
    if (_long.running) { flash("Подождите: " + _long._label); return false }
    lastError = ""
    progressInfo = null
    return run(_long, args, function(r) {
      progressInfo = null
      if (!r.ok) lastError = Model.actionErrorText(r.message)
      else if (okText) flash(typeof okText === "function" ? okText(r.data) : okText)
      if (after) after(r)
      refresh()
    }, label)
  }

  function flash(text) {
    flashText = text
    flashTimer.interval = Math.max(2500, String(text).length * 70)
    flashTimer.restart()
  }

  function notify(text, critical) {
    Quickshell.execDetached(["notify-send", "-a", "Zapret2", "-u", critical ? "critical" : "normal", "Zapret2", text])
  }

  // --- actions -------------------------------------------------------------
  function refresh() {
    run(_status, ["status"], function(r) {
      if (r.data && r.data.ok !== false) {
        st = r.data
        maybeAutostart()
      }
      if (blockcheckRunning && watched) refreshBlockcheck()
    }, "status")
  }

  function maybeAutostart() {
    if (_autostartDone || !st) return
    _autostartDone = true
    if (st.installed && st.settings && st.settings.autostart && st.active === "inactive")
      act(["on"], "включение", "Zapret2 включён при входе")
  }

  function turnOn() { act(["on"], "включение", "Обход включён", function(r) { if (r.ok && installed) runCheck() }) }
  function turnOff() { act(["off"], "выключение", "Обход выключен", function(r) { if (r.ok && installed) runCheck() }) }
  function toggle() {
    if (!installed) { openApp(); return }
    if (isOn) turnOff(); else turnOn()
  }

  // Choosing a game filter other than "off" needs ipsets: auto-enable them
  // when they were "none", so the game filter works without a second step.
  // The red warning row itself lives in App.qml (App lane removes it); the
  // state it needs (settings.game/settings.ipset) and this flash stay here.
  function setOption(key, value) {
    var v = String(value)
    if (key === "game" && v !== "off" && (settings.ipset || "loaded") === "none") {
      act(["set", "game", v], "настройка", "", function(r) {
        if (!r.ok) return
        act(["set", "ipset", "loaded"], "настройка", "IP-сети включены для игрового фильтра")
      })
      return
    }
    var text = key === "preset" ? "Стратегия: " + Model.presetTitle(v) : "Сохранено"
    act(["set", key, v], "настройка", text, function(r) {
      if (r.ok && key === "preset" && installed) runCheck()
    })
  }

  // Explicit-target toggles for the App settings switches (immune to the
  // ToggleSwitch.checked flip timing): App lane should call these from
  // onToggled instead of deriving on/off from `checked`.
  function toggleAutostart() { setOption("autostart", settings.autostart === true ? "off" : "on") }
  function toggleIpv6() { setOption("ipv6", settings.ipv6 !== false ? "off" : "on") }

  function runCheck() {
    longJob(["check"], "проверка", function(d) { return d ? Model.checkLine(d) : "Готово" })
  }

  function autopick(names) {
    var args = ["autopick"]
    if (names && names.length) args.push(names.join(","))
    longJob(args, "автоподбор", function(d) { return d ? "Выбрана стратегия " + Model.presetTitle(d.chosen) : "Готово" })
  }

  function stopLong() {
    if (_long.running) _long.signal(15)
  }

  function setup() {
    longJob(["setup"], "установка", function(d) { return "Zapret2 " + (d && d.version ? d.version : "") + " установлен" })
  }
  function updateApp() { longJob(["setup", "--app-only"], "обновление", "Системная часть обновлена") }
  function engineUpdate() { longJob(["engine", "update"], "обновление движка", function(d) { return "Движок " + (d && d.version ? d.version : "") }) }
  function updateLists() {
    longJob(["lists", "update"], "обновление списков", function(d) {
      var n = 0
      if (d && d.updated) for (var k in d.updated) n += d.updated[k]
      return "Списки обновлены: " + n + " записей"
    })
  }
  function updatePresets() {
    longJob(["presets", "update"], "обновление стратегий", function(d) {
      var n = 0
      if (d && d.updated)
        n = Array.isArray(d.updated) ? d.updated.length : Object.keys(d.updated).length
      return n > 0 ? "Стратегии обновлены: " + n : "Стратегии обновлены"
    })
  }
  function hostsSet(on) {
    longJob(["hosts", on ? "on" : "off"], "hosts", function(d) {
      if (d && d.on && typeof d.lines === "number")
        return "Hosts включён: " + d.lines + " записей"
      return on ? "Hosts включён" : "Hosts выключен"
    })
  }
  function clearDiscordCache() {
    act(["discord-cache", "clear"], "очистка кэша Discord", "", function(r) {
      if (r.ok) {
        var n = r.data && r.data.cleared ? r.data.cleared.length : 0
        flash(n > 0 ? "Кэш Discord очищен: " + n : "Кэш Discord очищен")
      }
    })
  }
  function removeAll(purge) {
    longJob(purge ? ["remove", "--purge"] : ["remove"], "удаление", "Zapret2 удалён из системы")
  }

  function loadText(args, cb) {
    var p = _aux.running ? _aux2 : _aux
    run(p, args, function(r) { cb(r) }, "чтение")
  }
  function saveList(name, text, cb, restart) {
    var args = ["list", "save", name]
    if (restart === false) args.push("--no-restart")
    act(args, "сохранение списка", "", cb, text)
  }
  function saveCustom(name, text, cb) { act(["custom", "save", name], "сохранение стратегии", "Стратегия сохранена", cb, text) }
  function removeCustom(name) { act(["custom", "rm", name], "удаление стратегии", "Стратегия удалена") }
  function presetText(name, cb) {
    var p = _aux.running ? _aux2 : _aux
    run(p, ["presets", "show", name], function(r) { cb(r) }, "чтение")
  }

  function runDoctor() {
    run(_aux, ["doctor"], function(r) { if (r.data) doctorItems = r.data.items || [] }, "диагностика")
  }
  function loadLogs() {
    run(_aux2, ["logs", "150"], function(r) {
      if (r.data) { logLines = r.data.lines || []; logNote = r.data.note || "" }
    }, "логи")
  }

  function blockcheckStart(domains, level) {
    var args = ["blockcheck", "start"].concat(domains || [])
    if (level) args = args.concat(["--level", level])
    act(args, "blockcheck", "blockcheck2 запущен: это может занять долго", function() { refreshBlockcheck() })
  }
  function blockcheckStop() { act(["blockcheck", "stop"], "остановка blockcheck", "blockcheck2 остановлен", function() { refreshBlockcheck() }) }
  function refreshBlockcheck() {
    run(_bc, ["blockcheck", "status"], function(r) { if (r.data && r.data.ok) blockcheck = r.data }, "blockcheck")
  }
  function blockcheckSave(index) {
    act(["blockcheck", "save", String(index)], "сохранение находки", "", function(r) {
      if (r.ok && r.data) flash("Сохранено как " + r.data.name)
    })
  }

  function openApp(tab) {
    var payload = "{}"
    if (tab !== undefined && tab !== null) payload = JSON.stringify({ tab: tab })
    if (shell && typeof shell.summon === "function") shell.summon(pluginId, payload)
    else Quickshell.execDetached(["omarchy-shell", "shell", "summon", pluginId, payload])
  }
  function toggleApp() {
    if (shell && typeof shell.toggle === "function") shell.toggle(pluginId, "{}")
    else Quickshell.execDetached(["omarchy-shell", "shell", "toggle", pluginId, "{}"])
  }

  // --- processes -----------------------------------------------------------
  // Inline components do not see this file's ids: the owner is handed in.
  component Slot: Process {
    id: proc
    property var owner: null
    property bool reportProgress: false
    property var _done: null
    property string _label: ""
    property string _input: ""
    property var _lines: []
    property int _code: 0
    clearEnvironment: true
    stdout: SplitParser {
      onRead: function(line) {
        proc._lines.push(line)
        if (proc._lines.length > 4000) proc._lines.shift()
        var o = Model.parseLine(line)
        if (o && o.progress && proc.reportProgress) proc.owner.progressInfo = o
      }
    }
    onStarted: if (_input !== "") { write(_input); stdinEnabled = false }
    // stdout may still deliver its last lines after the exit signal
    onExited: function(code) { _code = code; settle.restart() }
    property Timer settle: Timer { interval: 120; onTriggered: proc.owner.finish(proc, proc._code) }
  }

  Slot { id: _status; owner: root }
  Slot { id: _action; owner: root }
  Slot { id: _long; owner: root; reportProgress: true }
  Slot { id: _aux; owner: root }
  Slot { id: _aux2; owner: root }
  Slot { id: _bc; owner: root }

  Timer { id: flashTimer; onTriggered: root.flashText = "" }

  Timer {
    interval: root.blockcheckRunning && root.watched ? 2000 : root.watched ? 4000 : 20000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!_status.running) root.refresh()
  }

  Component.onCompleted: Quickshell.execDetached([manager, "desktop", "on"])

  IpcHandler {
    target: root.pluginId
    function toggle(): void { root.toggleApp() }
    function open(): void { root.openApp() }
    function close(): void { if (root.shell) root.shell.hide(root.pluginId) }
    function status(): string { return root.summary }
    function on(): string { root.turnOn(); return "ok" }
    function off(): string { root.turnOff(); return "ok" }
    function toggleBypass(): string { root.toggle(); return "ok" }
    function strategy(name: string): string { root.setOption("preset", name); return "ok" }
    function check(): string { root.runCheck(); return "ok" }
    function autopick(): string { root.autopick([]); return "ok" }
  }
}
