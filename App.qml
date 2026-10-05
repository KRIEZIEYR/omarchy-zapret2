import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "model/Zapret.js" as Model

/*
 * The app: a centered window summoned by the shell (launcher entry, the bar
 * popup, `omarchy-shell shell toggle krieziey.omarchy-zapret2 {}`).
 * Tabs: overview, strategies, lists, search (autopick + blockcheck2),
 * engine (update, doctor, logs, removal) and settings. All state comes from
 * the plugin service, which the shell hands in as `service`.
 */
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  readonly property var svc: service
  readonly property bool ready: service !== null

  readonly property string pluginId: "krieziey.omarchy-zapret2"
  property bool opened: false
  property bool closingFromHost: false
  property int tab: 0
  readonly property var tabs: ["Обзор", "Стратегии", "Списки", "Подбор", "Движок", "Настройки"]

  readonly property string fontFamily: Style.font.family
  readonly property string monoFamily: "monospace"
  readonly property color fg: Color.popups.text
  readonly property color bg: Color.popups.background
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.08)
  readonly property color line: Qt.rgba(fg.r, fg.g, fg.b, 0.18)
  readonly property color bad: Model.pickBad(Color.urgent, Color.popups.background, "#e06c75")

  function copyText(t) {
    copyProc.command = ["wl-copy", String(t)]
    copyProc.running = true
  }

  function fixQuic(s) {
    return String(s || "").split("может грузиться медленно (QUIC) — попробуйте другую стратегию").join("QUIC не проходит — видео может грузиться медленнее")
  }

  function open(payloadJson) {
    var p = {}
    try { p = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    if (p.tab !== undefined) tab = Math.max(0, Math.min(tabs.length - 1, p.tab | 0))
    opened = true
    closingFromHost = false
    window.visible = true
    if (ready) { svc.appOpen = true; svc.refresh() }
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
    opened = false
    if (ready) svc.appOpen = false
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  onServiceChanged: if (service && opened) { service.appOpen = true; service.refresh() }
  Component.onDestruction: if (ready) svc.appOpen = false

  onTabChanged: {
    if (!ready) return
    if (tab === 4) { svc.runDoctor(); svc.loadLogs() }
    if (tab === 3) { svc.refreshBlockcheck(); if (svc.doctorItems.length === 0) svc.runDoctor() }
  }

  Process {
    id: copyProc
    stdinEnabled: false
    onExited: function(code) {
      if (!root.ready) return
      root.svc.flash(code === 0 ? "Скопировано" : "wl-copy не найден")
    }
  }

  // --- small building blocks ---------------------------------------------
  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.Wrap
  }

  component Hint: Text {
    textFormat: Text.PlainText
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.75)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }

  component PrimaryButton: Button {
    selected: true
  }

  component Card: Rectangle {
    default property alias content: inner.data
    property alias spacing: inner.spacing
    Layout.fillWidth: true
    implicitHeight: inner.implicitHeight + Style.space(24)
    color: root.faint
    radius: Style.cornerRadius
    border.color: root.line
    border.width: 1
    ColumnLayout {
      id: inner
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(8)
    }
  }

  component PickRow: RowLayout {
    required property var row
    property int baseScore: -1
    property bool selected: false
    signal picked(string preset)
    HoverHandler { id: hover }
    TapHandler { onTapped: { if (row && !row.baseline) picked(row.preset) } }
    Label {
      Layout.preferredWidth: Style.space(180)
      text: ((row && row.chosen) ? "● " : "") + ((row && row.title) || "")
      font.bold: !!(row && row.chosen)
    }
    Rectangle {
      Layout.fillWidth: true
      height: Style.space(6)
      radius: height / 2
      color: root.faint
      Rectangle {
        width: parent.width * ((row && row.pct) || 0) / 100
        height: parent.height
        radius: parent.radius
        color: ((row && row.pct) || 0) === 100 ? Color.accent : (row && !row.baseline && baseScore >= 0 && (row.score || 0) < baseScore ? root.bad : root.dim)
      }
    }
    Hint {
      Layout.preferredWidth: Style.space(160)
      text: (row && row.error) ? String(row.error) : ((row && row.score) || 0) + "/" + ((row && row.total) || 0)
      elide: Text.ElideRight
      wrapMode: Text.NoWrap
    }
    PrimaryButton {
      visible: !!row && !row.baseline && (!root.ready || root.svc.preset !== row.preset)
      enabled: !!row && !row.baseline && root.ready && !root.svc.busy && root.svc.preset !== row.preset
      text: "Применить"
      onClicked: { picked(row.preset); root.svc.setOption("preset", row.preset) }
    }
  }

  component Editor: ScrollView {
    property alias text: area.text
    property alias readOnly: area.readOnly
    property alias placeholderText: area.placeholderText
    property alias area: area
    Layout.fillWidth: true
    Layout.fillHeight: true
    clip: true
    background: Rectangle { color: Qt.rgba(0, 0, 0, 0.18); border.color: root.line; border.width: 1; radius: Style.cornerRadius }
    TextArea {
      id: area
      color: root.fg
      placeholderTextColor: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.5)
      font.family: root.monoFamily
      font.pixelSize: Style.font.bodySmall
      selectByMouse: true
      wrapMode: TextEdit.NoWrap
      selectionColor: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
      background: null
      padding: Style.space(8)
    }
  }

  // --- window --------------------------------------------------------------
  // A regular toplevel window: Hyprland tiles, floats and closes it like any app.
  FloatingWindow {
    id: window
    title: "Zapret2"
    visible: false
    color: root.bg
    implicitWidth: Style.space(900)
    implicitHeight: Style.space(620)
    minimumSize: Qt.size(Style.space(640), Style.space(440))
    // closed by the window manager (Super+W, close button): tell the shell
    onVisibleChanged: if (!visible && !root.closingFromHost) root.dismiss()

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(e) {
        if ((e.modifiers & Qt.ControlModifier) && e.key >= Qt.Key_1 && e.key <= Qt.Key_6) {
          root.tab = e.key - Qt.Key_1
          e.accepted = true
        } else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_T && root.ready) {
          root.svc.toggle()
          e.accepted = true
        }
      }

      Rectangle {
        id: card
        anchors.fill: parent
        color: root.bg
        MouseArea { anchors.fill: parent; onClicked: keys.forceActiveFocus() }

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.space(16)
          spacing: Style.space(16)

          // sidebar
          ColumnLayout {
            Layout.preferredWidth: Style.space(170)
            Layout.fillHeight: true
            spacing: Style.space(6)

            RowLayout {
              spacing: Style.space(10)
              Layout.bottomMargin: Style.space(10)
              ZapretIcon {
                iconSize: Style.space(28)
                color: root.ready && root.svc.bypassState === "error" ? root.bad : root.fg
                filled: root.ready && root.svc.isOn
                warning: root.ready && root.svc.errorText !== ""
              }
              ColumnLayout {
                spacing: 0
                Text { text: "Zapret2"; color: root.ready && root.svc.isOn ? Color.accent : root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                Hint { text: root.ready ? ((root.svc.bypassState === "error" ? Model.stateText(root.svc.st) : (root.svc.isOn ? "● Включён" : "○ Выключен"))) : "Загрузка…"; color: root.ready && root.svc.bypassState === "error" ? root.bad : (root.ready && root.svc.isOn ? Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.75)) }
              }
            }

            Repeater {
              model: root.tabs
              delegate: RowLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: Style.space(6)
                Button {
                  Layout.fillWidth: true
                  leftAlign: true
                  text: modelData
                  selected: root.tab === index
                  tooltipText: "Ctrl+" + (index + 1)
                  onClicked: root.tab = index
                }
                Rectangle {
                  Layout.alignment: Qt.AlignVCenter
                  width: Style.space(8)
                  height: Style.space(8)
                  radius: width / 2
                  color: Color.accent
                  visible: index === 4 && root.ready && root.svc.installed && !root.svc.appCurrent && root.tab !== 0 && root.tab !== 4
                }
              }
            }

            Item { Layout.fillHeight: true }

            Hint {
              Layout.fillWidth: true
              visible: root.ready && root.svc.busy
              text: root.ready ? "Выполняется: " + root.svc.busyLabel + "…" : ""
            }
          }

          Rectangle { Layout.fillHeight: true; width: 1; color: root.line }

          // content
          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.space(10)

            Text {
              Layout.fillWidth: true
              visible: text !== ""
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: !root.ready ? "" : root.svc.errorText !== "" ? root.svc.errorText : root.svc.flashText
              color: root.ready && root.svc.errorText !== "" ? root.bad : Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Card {
              visible: root.ready && root.svc.reachable && !root.svc.installed
              Label { Layout.fillWidth: true; font.bold: true; text: "Движок zapret2 не установлен" }
              Hint {
                Layout.fillWidth: true
                text: "Установка скачает последний релиз bol-van/zapret2 с GitHub, сверит sha256 и разложит файлы в /opt/omarchy-zapret2 (root). "
                    + "Пароль спросят один раз. Дальше включение, стратегии, списки и blockcheck2 работают без пароля."
              }
              Button { bordered: true; text: root.ready && root.svc.busy ? "Установка…" : "Установить"; onClicked: root.svc.setup() }
            }

            Card {
              visible: root.ready && root.svc.installed && !root.svc.appCurrent && (root.tab === 0 || root.tab === 4)
              Label { Layout.fillWidth: true; text: "Новая версия плагина ждёт установки системной части. Нужен пароль." }
              Button { bordered: true; text: "Установить обновление"; onClicked: root.svc.updateApp() }
            }

            StackLayout {
              Layout.fillWidth: true
              Layout.fillHeight: true
              currentIndex: root.tab

              OverviewPage {}
              StrategiesPage {}
              ListsPage {}
              SearchPage {}
              EnginePage {}
              SettingsPage {}
            }
          }
        }
      }
    }
  }

  // --- pages ---------------------------------------------------------------
  component OverviewPage: ScrollView {
    id: ov
    property var expanded: ({})
    clip: true
    contentWidth: availableWidth
    ColumnLayout {
      width: parent.width
      spacing: Style.space(12)

      Card {
        id: headCard
        property bool isStale: {
          if (!root.ready) return false
          return Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult).action === "check"
        }
        property bool isNeutral: {
          if (!root.ready) return false
          var v = Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult)
          if (v.tone !== "neutral" || v.action !== "none") return false
          var t = String(v.text || "")
          return t.indexOf("без обхода") !== -1 || t.indexOf("не нужен") !== -1 || t.indexOf("Обход здесь не нужен") !== -1
        }
        RowLayout {
          Layout.fillWidth: true
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Text {
              Layout.fillWidth: true
              text: {
                if (!root.ready) return ""
                if (root.svc.bypassState === "error") return Model.stateText(root.svc.st)
                return root.svc.isOn ? "● Включён" : "○ Выключен"
              }
              color: root.ready && root.svc.bypassState === "error" ? root.bad : (root.ready && root.svc.isOn ? Color.accent : root.dim)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body * 1.4
              font.bold: true
            }
            Hint {
              text: !root.ready || !root.svc.installed ? "" :
                  "Стратегия " + Model.presetTitle(root.svc.preset) + " · движок " + (root.svc.st.engine || "?")
                  + (root.svc.st.restarts > 0 ? " · перезапусков " + root.svc.st.restarts : "")
            }
          }
          ToggleSwitch {
            enabled: root.ready && root.svc.installed
            checked: root.ready && root.svc.isOn
            busy: root.ready && root.svc.busy
            onToggled: root.svc.toggle()
          }
        }
        Text {
          Layout.fillWidth: true
          visible: text !== ""
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.body * 1.2
          text: {
            if (!root.ready) return ""
            var v = Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult)
            return root.fixQuic(v.text)
          }
          color: {
            if (!root.ready) return Color.popups.text
            var v = Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult)
            return v.tone === "good" ? Color.accent : (v.tone === "bad" || v.tone === "warn") ? root.bad : Color.popups.text
          }
        }
        Hint {
          Layout.fillWidth: true
          visible: !headCard.isStale && text !== ""
          text: {
            if (!root.ready) return ""
            var v = Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult)
            return v.note || ""
          }
        }
        RowLayout {
          Layout.fillWidth: true
          visible: headCard.isStale
          spacing: Style.space(8)
          Label {
            Layout.fillWidth: true
            color: root.bad
            text: {
              if (!root.ready) return ""
              var v = Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult)
              return "⚠ " + (v.note || "") + " — нажмите «Проверить» ниже"
            }
          }
        }
        RowLayout {
          Layout.fillWidth: true
          visible: !headCard.isNeutral
          property bool hasPick: root.ready && !!root.svc.autopickResult.time
          PrimaryButton {
            enabled: root.ready && root.svc.installed && !root.svc.busy
            visible: !parent.hasPick || !root.svc.isOn
            text: !parent.hasPick ? "Подобрать стратегию" : "Включить"
            onClicked: {
              if (!parent.hasPick) { root.tab = 3; root.svc.autopick([]) }
              else root.svc.toggle()
            }
          }
          Button {
            bordered: true
            enabled: root.ready && root.svc.installed && !root.svc.busy
            visible: parent.hasPick && root.ready && root.svc.isOn
            text: "Выключить"
            onClicked: root.svc.toggle()
          }
        }
        RowLayout {
          Layout.fillWidth: true
          visible: headCard.isNeutral
          Button {
            bordered: true
            enabled: root.ready && root.svc.installed && !root.svc.busy
            text: "Всё равно включить"
            onClicked: root.svc.turnOn()
          }
        }
      }

      Card {
        visible: root.ready && root.svc.installed && !root.svc.autopickResult.time
        RowLayout {
          Layout.fillWidth: true
          Label {
            Layout.fillWidth: true
            text: "Стратегия, которая работает у одного провайдера, у другого может ломать сайты. Подбор за пару минут найдёт подходящую."
          }
          Button { bordered: true; text: "Подобрать"; onClicked: { root.tab = 3; root.svc.autopick([]) } }
        }
      }

      Card {
        visible: root.ready && root.svc.installed
        property bool isStale: {
          if (!root.ready) return false
          return Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult).action === "check"
        }
        RowLayout {
          Layout.fillWidth: true
          Label { Layout.fillWidth: true; font.bold: true; text: "Доступность" }
          Hint { text: root.ready ? Model.ago(root.svc.check.time) : "" }
          Button { bordered: true; text: "Проверить"; onClicked: root.svc.runCheck() }
        }
        Repeater {
          model: root.ready ? Model.categories(root.svc.check) : []
          delegate: ColumnLayout {
            required property var modelData
            property string catKey: modelData.key
            Layout.fillWidth: true
            opacity: {
              if (!root.ready) return 1.0
              return Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult).action === "check" ? 0.5 : 1.0
            }
            spacing: Style.space(2)
            RowLayout {
              Layout.fillWidth: true
              TapHandler {
                onTapped: {
                  var e = Object.assign({}, ov.expanded)
                  e[catKey] = !e[catKey]
                  ov.expanded = e
                }
              }
              Label {
                Layout.fillWidth: true
                font.bold: !modelData.good
                color: modelData.good ? root.fg : root.bad
                text: {
                  var open = !!ov.expanded[catKey]
                  var glyph = modelData.good ? "✓ " : (modelData.ok > 0 ? "⚠ " : "✗ ")
                  var base = glyph + modelData.label + " " + modelData.ok + "/" + modelData.total
                  if (modelData.good) return (open ? "▾ " : "▸ ") + base
                  var hosts = (root.ready && root.svc.check.categories[modelData.key]) ? root.svc.check.categories[modelData.key].results : []
                  var failed = hosts.filter(function(h) { return !h.ok })
                  var quicOnly = failed.length > 0 && failed.every(function(h) { return h.http3 })
                  var reason = quicOnly ? "QUIC не проходит — видео может грузиться медленнее" : (failed.length > 0 ? Model.curlError(failed[0].error) : "не проходит")
                  return (open ? "▾ " : "▸ ") + base + " · " + reason
                }
              }
            }
            Repeater {
              model: root.ready && root.svc.check.categories[modelData.key] ? root.svc.check.categories[modelData.key].results : []
              delegate: RowLayout {
                required property var modelData
                visible: !!ov.expanded[catKey]
                Layout.fillWidth: true
                Hint {
                  Layout.fillWidth: true
                  text: (modelData.ok ? "✓ " : "✗ ") + modelData.url.replace("https://", "") + (modelData.http3 ? " (QUIC)" : "")
                  color: modelData.ok ? root.dim : root.bad
                }
                Hint {
                  text: modelData.ok ? Math.round(modelData.time * 1000) + " мс" : Model.curlError(modelData.error)
                  elide: Text.ElideRight
                  wrapMode: Text.NoWrap
                  Layout.maximumWidth: Style.space(260)
                }
              }
            }
          }
        }
      }
    }
  }

  component StrategiesPage: ColumnLayout {
    id: sp
    spacing: Style.space(10)
    property string editName: ""
    property bool editing: false
    property string selectedName: ""
    property string shownName: ""
    property string shownText: ""
    property bool showing: false
    property string showError: ""
    property var moreOpen: ({})
    property var tiesOpen: ({})
    property string filter: ""
    property string armDelete: ""
    property bool showAll: false
    property string pendingPreset: ""
    Timer { id: disarmTimer; interval: 4000; onTriggered: sp.armDelete = "" }
    Timer {
      id: pendingTimer
      interval: 600
      repeat: true
      running: sp.pendingPreset !== ""
      onTriggered: {
        if (!root.ready || root.svc.busy) return
        var n = sp.pendingPreset
        sp.pendingPreset = ""
        if (!root.svc.isOn || root.svc.preset !== n) root.svc.turnOn()
      }
    }
    onVisibleChanged: if (visible) Qt.callLater(scrollToActive)
    Component.onCompleted: if (visible) Qt.callLater(scrollToActive)

    function edit(name) {
      editing = true
      editName = name ? name.replace(/^my-/, "") : ""
      editor.text = ""
      if (name) root.svc.loadText(["custom", "show", name], function(r) { if (r.ok) editor.text = r.data.text })
      else editor.text = "# Своя стратегия: секции из опций nfqws2 (--lua-desync, --payload, --out-range).\n"
          + "[TCP_HTTP]\n--lua-desync=fake:blob=http_iana:tcp_md5:repeats=6\n--lua-desync=multisplit:pos=2,host+1\n"
          + "[TCP_TLS]\n--lua-desync=fake:blob=tls_google:tcp_md5:repeats=6\n--lua-desync=multisplit:pos=2,midsld\n"
          + "[TCP_GENERIC]\n--lua-desync=fake:blob=tls_google:tcp_md5:repeats=4\n--lua-desync=multisplit:pos=2\n"
          + "[QUIC]\n--lua-desync=fake:blob=quic_google:repeats=6\n"
    }

    function show(name) {
      showing = true
      shownName = name
      shownText = ""
      showError = "Загрузка…"
      root.svc.presetText(name, function(r) {
        if (r.ok) { shownText = r.data.text; showError = "" }
        else showError = r.message
      })
    }

    function copyAsOwn() {
      editing = true
      showing = false
      editName = shownName.replace(/^my-/, "").replace(/^fs-/, "")
      editor.text = shownText
    }

    function saveFullAsOwn() {
      var base = String(shownName || "").replace(/^my-/, "").replace(/^fs-/, "")
      if (base === "") base = "full"
      root.svc.saveCustom(base, shownText, function(r) { if (r.ok) showing = false })
    }

    function recommendedName() {
      if (root.ready && root.svc.autopickResult && root.svc.autopickResult.time) {
        var c = String(root.svc.autopickResult.chosen || "")
        if (c !== "" && c !== "(off)") return c
      }
      return "fs-general"
    }

    function recommendedText() {
      var r = sp.pickRow(sp.recommendedName())
      if (typeof Model.breaksText === "function") return Model.breaksText(r)
      return "не проверялась"
    }

    function totalPresets() {
      if (!root.ready || !root.svc.presets) return 0
      return root.svc.presets.length
    }

    function isSectionFormat(text) { return String(text || "").indexOf("[TCP_") !== -1 }

    function pickRow(name) {
      var rows = Model.autopickRows(root.svc.autopickResult)
      for (var i = 0; i < rows.length; i++) if (rows[i].preset === name) return rows[i]
      return null
    }

    function baseScore() {
      var rows = Model.autopickRows(root.svc.autopickResult)
      for (var i = 0; i < rows.length; i++) if (rows[i].baseline) return rows[i].score
      return -1
    }

    function isWorse(name) {
      var r = pickRow(name)
      if (!r || r.baseline || (r.total | 0) === 0) return false
      var b = baseScore()
      return b >= 0 && r.score < b
    }

    function isTested(name) {
      var r = pickRow(name)
      return !!(r && ((r.total | 0) > 0 || r.error !== ""))
    }

    function flowsealSource(name) {
      var s = String(name || "")
      if (s.indexOf("fs-") !== 0) return ""
      var rest = s.substring(3)
      var dash = rest.indexOf("-")
      if (dash === -1) return rest + ".bat"
      return rest.substring(0, dash) + " (" + rest.substring(dash + 1).split("-").join(" ").toUpperCase() + ").bat"
    }

    function rowSubtitle(p) {
      var r = sp.pickRow(p.name)
      var t = ""
      if (typeof Model.breaksText === "function") t = Model.breaksText(r)
      else if (r && (r.total | 0) > 0) t = r.score + "/" + r.total + " в подборе"
      else if (r && r.error !== "") t = r.error
      else t = "не проверялась"
      if (sp.isWorse(p.name)) t += " · ⚠ хуже, чем без обхода"
      return t
    }

    function groups() {
      if (!root.ready) return []
      var order = []
      var per = {}
      var list = root.svc.presets.slice()
      var f = sp.filter.trim().toLowerCase()
      if (f !== "") {
        list = list.filter(function(p) { return Model.presetTitle(p.name).toLowerCase().indexOf(f) !== -1 })
      }
      for (var j = 0; j < list.length; j++) {
        var g = list[j].group || ""
        if (order.indexOf(g) === -1) { order.push(g); per[g] = [] }
        per[g].push(list[j])
      }
      var out = []
      for (var k = 0; k < order.length; k++) {
        var items = per[order[k]].slice()
        items.sort(function(a, b) {
          var ta = sp.isTested(a.name) ? 0 : 1, tb = sp.isTested(b.name) ? 0 : 1
          if (ta !== tb) return ta - tb
          var ra = sp.pickRow(a.name), rb = sp.pickRow(b.name)
          var sa = ra ? ra.score : -1, sb = rb ? rb.score : -1
          if (sa !== sb) return sb - sa
          var ca = (ra && ra.chosen) ? 0 : 1, cb = (rb && rb.chosen) ? 0 : 1
          if (ca !== cb) return ca - cb
          return a.name.localeCompare(b.name, undefined, { numeric: true })
        })
        var tested = [], untested = []
        for (var m = 0; m < items.length; m++) {
          if (sp.isTested(items[m].name)) tested.push(items[m])
          else untested.push(items[m])
        }
        out.push({ group: order[k], tested: tested, untested: untested })
      }
      return out
    }

    function groupRows(g) {
      var best = -1
      for (var ti = 0; ti < g.tested.length; ti++) {
        var rr = sp.pickRow(g.tested[ti].name)
        var sc = rr ? (rr.score | 0) : -1
        if (sc > best) best = sc
      }
      var firstBest = true
      var head = [], tied = []
      for (var hi = 0; hi < g.tested.length; hi++) {
        var hr = sp.pickRow(g.tested[hi].name)
        var hs = hr ? (hr.score | 0) : -1
        if (hs === best && best >= 0 && !firstBest) tied.push(g.tested[hi])
        else {
          if (hs === best && best >= 0) firstBest = false
          head.push(g.tested[hi])
        }
      }
      var rows = head.slice()
      if (tied.length > 0) {
        if (sp.tiesOpen[g.group]) rows = rows.concat(tied).concat([{ name: "", tiesCollapse: true, group: g.group, tiesCount: tied.length }])
        else rows.push({ name: "", tiesExpander: tied.length, group: g.group })
      }
      if (g.untested.length === 0) return rows
      if (sp.moreOpen[g.group]) return rows.concat(g.untested).concat([{ name: "", collapse: true, group: g.group }])
      rows.push({ name: "", expander: g.untested.length, group: g.group })
      return rows
    }

    function toggleTies(group) {
      var e = Object.assign({}, sp.tiesOpen)
      e[group] = !e[group]
      sp.tiesOpen = e
    }

    function toggleMore(group) {
      var e = Object.assign({}, sp.moreOpen)
      e[group] = !e[group]
      sp.moreOpen = e
    }

    function scrollToActive() {
      if (!root.ready || !root.svc.preset) return
      var groups = sp.groups()
      for (var gi = 0; gi < groups.length; gi++) {
        var rows = sp.groupRows(groups[gi])
        for (var ri = 0; ri < rows.length; ri++) {
          if (rows[ri].name !== "" && rows[ri].name === root.svc.preset) {
            var gItem = groupRep.itemAt(gi)
            if (gItem && gItem.rowsRep) {
              var rItem = gItem.rowsRep.itemAt(ri)
              if (rItem) stratScroll.contentItem.contentY = Math.max(0, gItem.y + rItem.y - stratScroll.height / 2)
            }
            return
          }
        }
        var un = groups[gi].untested
        for (var ui = 0; ui < un.length; ui++) {
          if (un[ui].name === root.svc.preset) { sp.toggleMore(groups[gi].group); Qt.callLater(scrollToActive); return }
        }
      }
    }

    Card {
      visible: !sp.editing && !sp.showing
      Label { Layout.fillWidth: true; font.bold: true; text: "Рекомендуемая" }
      Label { Layout.fillWidth: true; text: Model.presetTitle(sp.recommendedName()) }
      Hint { Layout.fillWidth: true; text: sp.recommendedText() }
      RowLayout {
        Layout.fillWidth: true
        PrimaryButton {
          enabled: root.ready && root.svc.installed && !root.svc.busy
          text: "Включить её"
          onClicked: {
            var n = sp.recommendedName()
            if (root.svc.preset !== n) root.svc.setOption("preset", n)
            sp.pendingPreset = n
          }
        }
      }
    }
    RowLayout {
      Layout.fillWidth: true
      visible: !sp.editing && !sp.showing
      Button { bordered: true; text: "Подобрать автоматически"; onClicked: { root.tab = 3; root.svc.autopick([]) } }
      Button { bordered: true; text: "Обновить стратегии из Flowseal"; onClicked: root.svc.updatePresets() }
      Button { bordered: true; text: "Новая стратегия"; onClicked: sp.edit("") }
    }
    RowLayout {
      Layout.fillWidth: true
      visible: !sp.editing && !sp.showing
      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: sp.showAll = !sp.showAll }
      Label { Layout.fillWidth: true; font.bold: true; text: "Все стратегии (" + sp.totalPresets() + ") " + (sp.showAll ? "▾" : "▸") }
    }
    TextField {
      Layout.fillWidth: true
      visible: !sp.editing && !sp.showing && sp.showAll
      placeholderText: "Найти стратегию"
      text: sp.filter
      onTextChanged: sp.filter = text
    }

    ScrollView {
      id: stratScroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: !sp.editing && !sp.showing && sp.showAll
      clip: true
      contentWidth: availableWidth
      ColumnLayout {
        width: parent.width
        spacing: Style.space(10)
        Repeater {
          id: groupRep
          model: sp.groups()
          delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            Layout.topMargin: Style.space(8)
            spacing: Style.space(4)
            Label {
              Layout.fillWidth: true
              font.bold: true
              color: root.dim
              text: typeof Model.groupTitle === "function" ? Model.groupTitle(modelData.group) : modelData.group
            }
            Rectangle {
              Layout.fillWidth: true
              height: 1
              color: root.line
            }
            Repeater {
              id: rowsRep
              model: sp.groupRows(modelData)
              delegate: Rectangle {
                id: stratRect
                required property var modelData
                property bool isSpecial: modelData.expander !== undefined || modelData.collapse === true || modelData.tiesExpander !== undefined || modelData.tiesCollapse === true
                property bool isActive: !isSpecial && root.ready && root.svc.preset === modelData.name
                property bool isBest: {
                  if (isSpecial) return false
                  var br = sp.pickRow(modelData.name)
                  return !!(br && br.chosen)
                }
                property string flowSrc: !isSpecial ? sp.flowsealSource(modelData.name) : ""
                Layout.fillWidth: true
                height: stratRow.implicitHeight + Style.space(14)
                radius: Style.cornerRadius
                color: isActive
                         ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
                       : hover.hovered ? root.faint : "transparent"
                border.color: isActive ? Color.accent
                            : !isSpecial && sp.selectedName === modelData.name ? root.line : "transparent"
                HoverHandler { id: hover }
                ToolTip.visible: hover.hovered && stratRect.flowSrc !== ""
                ToolTip.text: stratRect.flowSrc
                TapHandler {
                  onTapped: {
                    if (modelData.expander !== undefined || modelData.collapse === true) sp.toggleMore(modelData.group)
                    else if (modelData.tiesExpander !== undefined || modelData.tiesCollapse === true) sp.toggleTies(modelData.group)
                    else {
                      sp.selectedName = modelData.name
                      if (sp.armDelete !== "" && sp.armDelete !== modelData.name) sp.armDelete = ""
                    }
                  }
                }
                RowLayout {
                  id: stratRow
                  anchors.fill: parent
                  anchors.margins: Style.space(7)
                  Label {
                    Layout.fillWidth: true
                    visible: stratRect.isSpecial
                    color: root.dim
                    text: modelData.collapse === true ? "▾ Свернуть" : modelData.tiesCollapse === true ? "▾ Свернуть" : modelData.tiesExpander !== undefined ? "▸ ещё " + modelData.tiesExpander + " с тем же результатом" : "▸ Ещё " + modelData.expander + " не проверялись"
                  }
                  ColumnLayout {
                    Layout.fillWidth: true
                    visible: !stratRect.isSpecial
                    spacing: 0
                    RowLayout {
                      Layout.fillWidth: true
                      spacing: Style.space(6)
                      Label { Layout.fillWidth: true; text: Model.presetTitle(modelData.name); font.bold: true }
                      Rectangle {
                        visible: stratRect.isActive
                        radius: Style.space(4)
                        border.color: Color.accent
                        border.width: 1
                        color: "transparent"
                        Text { anchors.fill: parent; anchors.margins: Style.space(2); leftPadding: Style.space(4); rightPadding: Style.space(4); text: "активна"; color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                      }
                      Rectangle {
                        visible: stratRect.isBest
                        radius: Style.space(4)
                        border.color: root.line
                        border.width: 1
                        color: "transparent"
                        Text { anchors.fill: parent; anchors.margins: Style.space(2); leftPadding: Style.space(4); rightPadding: Style.space(4); text: "лучшая"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                      }
                    }
                    Hint {
                      Layout.fillWidth: true
                      color: sp.isWorse(modelData.name) ? root.bad : root.dim
                      text: sp.rowSubtitle(modelData)
                    }
                    Hint {
                      Layout.fillWidth: true
                      visible: stratRect.flowSrc !== ""
                      color: root.dim
                      text: stratRect.flowSrc
                    }
                  }
                  PrimaryButton {
                    visible: !stratRect.isSpecial && sp.selectedName === modelData.name
                    enabled: root.svc.preset !== modelData.name
                    text: "Применить"
                    onClicked: root.svc.setOption("preset", modelData.name)
                  }
                  Button {
                    visible: !stratRect.isSpecial && sp.selectedName === modelData.name
                    bordered: true
                    text: "Показать"
                    onClicked: sp.show(modelData.name)
                  }
                  Button { visible: !stratRect.isSpecial && modelData.name.indexOf("my-") === 0; text: "Изменить"; onClicked: sp.edit(modelData.name) }
                  Button {
                    visible: !stratRect.isSpecial && modelData.name.indexOf("my-") === 0 && root.svc.preset !== modelData.name
                    foreground: root.bad
                    text: sp.armDelete === modelData.name ? "Точно удалить?" : "Удалить"
                    onClicked: {
                      if (sp.armDelete === modelData.name) { sp.armDelete = ""; disarmTimer.stop(); root.svc.removeCustom(modelData.name) }
                      else { sp.armDelete = modelData.name; disarmTimer.restart() }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: sp.showing
      spacing: Style.space(8)
      RowLayout {
        Layout.fillWidth: true
        Label { Layout.fillWidth: true; font.bold: true; text: Model.presetTitle(sp.shownName) }
        Button { text: "Закрыть"; onClicked: sp.showing = false }
      }
      Hint {
        Layout.fillWidth: true
        visible: sp.showError !== ""
        text: sp.showError
      }
      Hint {
        Layout.fillWidth: true
        visible: sp.shownText !== "" && !sp.isSectionFormat(sp.shownText)
        text: "Полный пресет Flowseal: его можно только посмотреть. Свои стратегии используют формат секций ([TCP_HTTP], [TCP_TLS], …)."
      }
      Editor {
        readOnly: true
        text: sp.shownText
      }
      RowLayout {
        PrimaryButton {
          visible: root.ready && root.svc.preset !== sp.shownName
          text: "Применить"
          onClicked: root.svc.setOption("preset", sp.shownName)
        }
        Button {
          bordered: true
          visible: sp.shownText !== "" && sp.isSectionFormat(sp.shownText)
          text: "Скопировать как свою"
          onClicked: sp.copyAsOwn()
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: sp.editing
      spacing: Style.space(8)
      RowLayout {
        Layout.fillWidth: true
        Label { text: "Имя:" }
        TextField {
          id: nameField
          Layout.preferredWidth: Style.space(220)
          text: sp.editName
          placeholderText: "например home"
          onTextChanged: sp.editName = text
        }
        Hint { Layout.fillWidth: true; text: "Разрешены только --lua-desync (функции zapret-antidpi), --payload, --out-range/--in-range; блобы: tls_google, tls_max, quic_google, http_iana, stun, zero, fake_default_*" }
      }
      Editor { id: editor }
      RowLayout {
        PrimaryButton {
          text: "Сохранить"
          enabled: sp.editName.trim() !== ""
          onClicked: root.svc.saveCustom(sp.editName.trim(), editor.text, function(r) { if (r.ok) sp.editing = false })
        }
        Button { text: "Отмена"; onClicked: sp.editing = false }
      }
    }
  }

  component ListsPage: ColumnLayout {
    id: lp
    spacing: Style.space(10)
    property string current: "list-general-user"
    readonly property bool editable: current.indexOf("-user") !== -1
    property string info: ""
    property string loadedText: ""
    readonly property var names: [
      { value: "list-general-user", label: "Мои сайты (через обход)" },
      { value: "list-exclude-user", label: "Мои исключения (без обхода)" },
      { value: "ipset-all-user", label: "Мои IP-сети (через обход)" },
      { value: "ipset-exclude-user", label: "Мои IP-исключения" },
      { value: "list-general", label: "Общий список (только чтение)" },
      { value: "list-google", label: "YouTube/Google (только чтение)" },
      { value: "list-exclude", label: "Исключения (только чтение)" },
      { value: "ipset-all", label: "IP-сети (только чтение)" },
      { value: "ipset-exclude", label: "IP-исключения (только чтение)" }
    ]

    function load() {
      if (!root.ready) return
      listEditor.text = ""
      loadedText = ""
      info = "Загрузка…"
      root.svc.loadText(["list", "show", current], function(r) {
        if (!r.ok) { info = r.message; return }
        listEditor.text = r.data.text + (r.data.text ? "\n" : "")
        loadedText = listEditor.text
        info = r.data.count + " строк" + (r.data.truncated ? " (показаны первые 5000)" : "")
      })
    }
    function savedMessage(count, dropped) {
      return "Сохранено: " + count + " строк, отброшено " + dropped
    }
    onCurrentChanged: load()
    Component.onCompleted: load()

    RowLayout {
      Layout.fillWidth: true
      Dropdown {
        Layout.preferredWidth: Style.space(320)
        showLabel: false
        value: lp.current
        options: lp.names
        onChanged: function(v) { lp.current = v }
      }
      Label {
        visible: lp.editable && listEditor.text !== lp.loadedText
        text: "•"
        color: Color.accent
        font.bold: true
      }
      Hint { Layout.fillWidth: true; text: lp.info }
      Button { bordered: true; text: "Обновить списки из Flowseal"; onClicked: root.svc.updateLists() }
    }
    Hint {
      Layout.fillWidth: true
      text: lp.editable ? "По одному домену (поддомены включаются сами) или IP/CIDR на строку. Неверные строки отбрасываются. Сохранение перезапускает обход."
                        : "Встроенный список. Свои записи добавляйте в «Мои …»."
    }
    Editor {
      id: listEditor
      readOnly: !lp.editable
      placeholderText: "example.com\nsub.example.org\n# по одному домену на строку"
    }
    RowLayout {
      visible: lp.editable
      PrimaryButton {
        text: "Сохранить"
        onClicked: root.svc.saveList(lp.current, listEditor.text, function(r) {
          if (r.ok) {
            var msg = lp.savedMessage(r.data.count, r.data.dropped || 0)
            root.svc.flash(msg)
            lp.loadedText = listEditor.text
            lp.info = msg
          }
        })
      }
      Hint { text: Model.countLines(listEditor.text) + " строк" }
    }
  }

  component SearchPage: ScrollView {
    id: se
    property bool showFull: false
    property string pickSel: ""
    property bool tiesOpen: false
    property var pickGroup: Model.groupSearchRows(Model.autopickRows(root.ready ? root.svc.autopickResult : null))
    property int pickBase: pickGroup && pickGroup.baseline ? (Number(pickGroup.baseline.score) || 0) : -1
    property string failingHosts: {
      if (!root.ready) return "youtube.com discord.com"
      var cats = (root.svc.check && root.svc.check.categories) ? root.svc.check.categories : {}
      var out = []
      for (var k in cats) {
        var rs = cats[k].results || []
        for (var i = 0; i < rs.length; i++) {
          if (rs[i].ok) continue
          var h = rs[i].host || ""
          if (!h && rs[i].url) h = String(rs[i].url).replace(/^https?:\/\//, "").split("/")[0]
          if (h && out.indexOf(h) === -1) out.push(h)
        }
      }
      return out.length > 0 ? out.join(" ") : "youtube.com discord.com"
    }
    clip: true
    contentWidth: availableWidth
    ColumnLayout {
      width: parent.width
      spacing: Style.space(12)

      Card {
        RowLayout {
          Layout.fillWidth: true
          Label { Layout.fillWidth: true; font.bold: true; text: "Быстрый подбор" }
          PrimaryButton {
            visible: !(root.ready && root.svc.busyLabel === "автоподбор")
            text: "Запустить"
            onClicked: root.svc.autopick([])
          }
          Button {
            bordered: true
            visible: root.ready && root.svc.busyLabel === "автоподбор"
            text: "Остановить"
            onClicked: root.svc.stopLong()
          }
        }
        Hint {
          Layout.fillWidth: true
          text: "Включает стратегии по очереди и проверяет YouTube, Discord, Google и Cloudflare. Останавливается на первой, где открывается всё, иначе оставляет лучшую. Пароль не нужен, занимает 1–3 минуты."
        }
        Label {
          Layout.fillWidth: true
          visible: root.ready && root.svc.autopickResult.notNeeded === true && root.svc.busyLabel !== "автоподбор"
          color: Color.accent
          text: "Без обхода открывается не хуже: обход сейчас не нужен, или он уже работает на роутере или в VPN"
        }
        Label {
          visible: root.ready && root.svc.progressInfo !== null && root.svc.busyLabel === "автоподбор"
          text: !root.ready || !root.svc.progressInfo ? ""
                : root.svc.progressInfo.step === 0 ? "Замер без обхода…"
                : "Шаг " + root.svc.progressInfo.step + " из " + root.svc.progressInfo.of + ": " + Model.presetTitle(root.svc.progressInfo.preset)
        }
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.ready && se.pickGroup.baseline !== null
          spacing: Style.space(4)
          PickRow {
            visible: se.pickGroup.baseline !== null
            row: se.pickGroup.baseline || {}
            baseScore: se.pickBase
            selected: se.pickSel !== "" && se.pickGroup.baseline !== null && se.pickSel === se.pickGroup.baseline.preset
            onPicked: function(p) { se.pickSel = p }
          }
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.line
            visible: se.pickGroup.best !== null
          }
          PickRow {
            visible: se.pickGroup.best !== null
            row: se.pickGroup.best || {}
            baseScore: se.pickBase
            selected: se.pickSel !== "" && se.pickGroup.best !== null && se.pickSel === se.pickGroup.best.preset
            onPicked: function(p) { se.pickSel = p }
          }
          RowLayout {
            Layout.fillWidth: true
            visible: se.pickGroup.ties.length > 0
            TapHandler { onTapped: se.tiesOpen = !se.tiesOpen }
            Label {
              Layout.fillWidth: true
              color: root.dim
              text: "ещё " + se.pickGroup.ties.length + " с тем же результатом " + (se.tiesOpen ? "▾" : "▸")
            }
          }
          Repeater {
            model: se.tiesOpen ? se.pickGroup.ties : []
            delegate: PickRow {
              required property var modelData
              row: modelData
              baseScore: se.pickBase
              selected: se.pickSel !== "" && se.pickSel === modelData.preset
              onPicked: function(p) { se.pickSel = p }
            }
          }
          Repeater {
            model: se.pickGroup.rest
            delegate: PickRow {
              required property var modelData
              row: modelData
              baseScore: se.pickBase
              selected: se.pickSel !== "" && se.pickSel === modelData.preset
              onPicked: function(p) { se.pickSel = p }
            }
          }
          Hint {
            Layout.fillWidth: true
            visible: root.ready && root.svc.autopickResult.time !== undefined && (root.svc.autopickResult.rows || []).length > 0
            text: "● — выбрана сейчас"
          }
        }
      }

      Card {
        RowLayout {
          Layout.fillWidth: true
          Label { Layout.fillWidth: true; font.bold: true; text: "Глубокий поиск: blockcheck2" }
          Button {
            bordered: true
            enabled: {
              if (!root.ready || root.svc.blockcheckRunning) return true
              var items = root.svc.doctorItems || []
              for (var i = 0; i < items.length; i++) {
                if (items[i].name === "host/nslookup" && !items[i].ok) return false
                if (items[i].name === "No VPN tunnel" && !items[i].ok) return false
              }
              return true
            }
            text: root.ready && root.svc.blockcheckRunning ? "Остановить" : "Запустить"
            onClicked: root.svc.blockcheckRunning ? root.svc.blockcheckStop()
                       : root.svc.blockcheckStart(domains.text.split(/[\s,]+/).filter(function(d) { return d !== "" }), level.value)
          }
        }
        Hint {
          Layout.fillWidth: true
          visible: {
            if (!root.ready || root.svc.blockcheckRunning) return false
            var items = root.svc.doctorItems || []
            for (var i = 0; i < items.length; i++)
              if (items[i].name === "host/nslookup" && !items[i].ok) return true
            return false
          }
          color: root.bad
          text: "нужен bind: omarchy pkg add bind"
        }
        Hint {
          Layout.fillWidth: true
          visible: {
            if (!root.ready || root.svc.blockcheckRunning) return false
            var items = root.svc.doctorItems || []
            for (var i = 0; i < items.length; i++)
              if (items[i].name === "No VPN tunnel" && !items[i].ok) return true
            return false
          }
          text: "включён VPN-туннель: blockcheck2 бессмыслен"
        }
        Hint {
          Layout.fillWidth: true
          text: "Официальный перебор стратегий zapret2. Обход на время поиска выключается. quick — минуты, standard и force — до часа и дольше. Найденное можно сохранить как свою стратегию."
        }
        RowLayout {
          Layout.fillWidth: true
          TextField { id: domains; Layout.fillWidth: true; text: se.failingHosts; placeholderText: "домены через пробел" }
          Dropdown {
            id: level
            Layout.preferredWidth: Style.space(160)
            showLabel: false
            value: "quick"
            options: [{ value: "quick", label: "быстрый" }, { value: "standard", label: "обычный" }, { value: "force", label: "полный" }]
            onChanged: function(v) { value = v }
          }
        }
        Repeater {
          model: root.ready && root.svc.blockcheck ? root.svc.blockcheck.found : []
          delegate: RowLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              Label { Layout.fillWidth: true; text: Model.findingTitle(modelData); font.bold: true }
              Hint { Layout.fillWidth: true; text: modelData.args; font.family: root.monoFamily }
            }
            Button { text: "Сохранить"; onClicked: root.svc.blockcheckSave(index) }
          }
        }
        Hint {
          visible: root.ready && root.svc.blockcheck !== null && root.svc.blockcheck.lines > 0
          text: {
            if (!root.ready || !root.svc.blockcheck) return ""
            var bc = root.svc.blockcheck
            var prefix = bc.done ? "Готово. " : root.svc.blockcheckRunning ? "Идёт поиск… " : ""
            var tail = bc.tail || []
            for (var i = tail.length - 1; i >= 0; i--) {
              var s = String(tail[i])
              if (s.substring(0, 2) === "- " || s.charAt(0) === "*") return prefix + (typeof Model.blockcheckPhase === "function" ? Model.blockcheckPhase(s) : s)
            }
            return prefix + bc.lines + " строк журнала"
          }
        }
        RowLayout {
          Layout.fillWidth: true
          visible: root.ready && root.svc.blockcheck !== null && root.svc.blockcheck.lines > 0
          Label { Layout.fillWidth: true; text: "Показать весь журнал" }
          ToggleSwitch { checked: se.showFull; onToggled: se.showFull = checked }
        }
        Editor {
          Layout.preferredHeight: Style.space(220)
          Layout.fillHeight: false
          readOnly: true
          visible: root.ready && root.svc.blockcheck !== null && root.svc.blockcheck.lines > 0
          text: {
            if (!root.ready || !root.svc.blockcheck) return ""
            var tail = root.svc.blockcheck.tail
            if (se.showFull) return tail.join("\n")
            return tail.filter(function(l) {
              var s = String(l)
              return s.substring(0, 5) === "!!!!!" || s.charAt(0) === "*" || s.indexOf("AVAILABLE") !== -1 || s.toLowerCase().indexOf("working strategy") !== -1
            }).join("\n")
          }
          area.onTextChanged: area.cursorPosition = area.length
        }
      }
    }
  }

  component EnginePage: ScrollView {
    id: ep
    clip: true
    contentWidth: availableWidth
    property bool armRemove: false
    Timer { id: armRemoveTimer; interval: 4000; onTriggered: ep.armRemove = false }
    ColumnLayout {
      width: parent.width
      spacing: Style.space(12)

      Card {
        Label { font.bold: true; text: "Движок: " + (root.ready && root.svc.st && root.svc.st.engine ? root.svc.st.engine : "не установлен") }
        Hint { Layout.fillWidth: true; text: "bol-van/zapret2: nfqws2 + Lua. Обновление скачивает последний релиз, сверяет sha256 и спрашивает пароль. Предыдущая версия остаётся рядом." }
        RowLayout {
          Button { bordered: true; text: "Обновить движок"; enabled: root.ready && root.svc.installed; onClicked: root.svc.engineUpdate() }
          Button { bordered: true; visible: !root.ready || root.svc.appCurrent; text: "Обновить системную часть"; enabled: root.ready && root.svc.installed; onClicked: root.svc.updateApp() }
        }
      }

      Card {
        RowLayout {
          Layout.fillWidth: true
          Label { Layout.fillWidth: true; font.bold: true; text: "Диагностика" }
          Button { bordered: true; text: "Повторить"; onClicked: root.svc.runDoctor() }
        }
        Repeater {
          model: root.ready ? root.svc.doctorItems : []
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Label { Layout.preferredWidth: Style.space(220); text: (modelData.ok ? "✓ " : "✗ ") + (typeof Model.doctorName === "function" ? Model.doctorName(modelData.name) : modelData.name); color: modelData.ok ? root.fg : root.bad }
            Hint {
              Layout.fillWidth: true
              visible: text !== ""
              text: {
                var d = Model.doctorDetail(modelData.name, modelData.detail)
                var dn = typeof Model.doctorName === "function" ? Model.doctorName(modelData.name) : modelData.name
                if ((modelData.name === "Setup" || dn === "Установка") && root.ready && root.svc.st && root.svc.st.engine && d.indexOf(String(root.svc.st.engine)) !== -1) return ""
                return d
              }
            }
            Button {
              visible: !modelData.ok && (String(modelData.name).indexOf("host") !== -1 || String(modelData.name).indexOf("nslookup") !== -1 || String(modelData.detail).indexOf("bind") !== -1)
              text: "Скопировать команду"
              onClicked: root.copyText("omarchy pkg add bind")
            }
            Button {
              visible: !modelData.ok && String(modelData.name).indexOf("Plugin and system copy") !== -1
              text: "Установить обновление"
              onClicked: root.svc.updateApp()
            }
          }
        }
      }

      Card {
        RowLayout {
          Layout.fillWidth: true
          Label { Layout.fillWidth: true; font.bold: true; text: "Журнал службы" }
          Button { bordered: true; text: "Обновить"; onClicked: root.svc.loadLogs() }
        }
        Hint { visible: root.ready && root.svc.logNote !== ""; Layout.fillWidth: true; text: root.ready ? root.svc.logNote : "" }
        Editor {
          Layout.preferredHeight: Style.space(240)
          Layout.fillHeight: false
          readOnly: true
          area.wrapMode: TextEdit.Wrap
          text: root.ready ? root.svc.logLines.map(function(l) { return Model.shortLog(l) }).join("\n") : ""
        }
      }

      Card {
        visible: root.ready && root.svc.installed
        Label { font.bold: true; text: "Удаление" }
        Hint { Layout.fillWidth: true; text: "Останавливает обход и удаляет всё, что поставила установка: /opt/omarchy-zapret2, юниты, правило polkit. Ваши списки и стратегии в /var/lib/omarchy-zapret2 остаются, если не выбрать «вместе с данными»." }
        RowLayout {
          Button { bordered: true; foreground: root.bad; text: ep.armRemove ? "Точно удалить?" : "Удалить"; onClicked: { if (ep.armRemove) { ep.armRemove = false; armRemoveTimer.stop(); root.svc.removeAll(false) } else { ep.armRemove = true; armRemoveTimer.restart() } } }
          Button { visible: ep.armRemove; foreground: root.bad; text: "Вместе с данными"; onClicked: { ep.armRemove = false; armRemoveTimer.stop(); root.svc.removeAll(true) } }
          Button { visible: ep.armRemove; text: "Отмена"; onClicked: { ep.armRemove = false; armRemoveTimer.stop() } }
        }
      }
    }
  }

  component SettingsPage: ScrollView {
    id: stp
    property bool showExtra: false
    property bool hostsConfirm: false
    Timer { id: hostsTimer; interval: 4000; onTriggered: stp.hostsConfirm = false }
    clip: true
    contentWidth: availableWidth
    ColumnLayout {
      width: parent.width
      spacing: Style.space(12)
      enabled: root.ready && root.svc.installed

      Card {
        RowLayout {
          Layout.fillWidth: true
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label { Layout.fillWidth: true; font.bold: true; text: "Включать при входе" }
            Hint { Layout.fillWidth: true; text: "Шелл включает обход после входа в систему" }
          }
          ToggleSwitch { checked: root.ready && root.svc.settings.autostart === true; onToggled: root.svc.toggleAutostart() }
        }
        RowLayout {
          Layout.fillWidth: true
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label { Layout.fillWidth: true; font.bold: true; text: "IPv6" }
            Hint { Layout.fillWidth: true; text: "Обрабатывать и IPv6-соединения" }
          }
          ToggleSwitch { checked: root.ready && root.svc.settings.ipv6 !== false; onToggled: root.svc.toggleIpv6() }
        }
      }

      Card {
        Dropdown {
          Layout.fillWidth: true
          label: "Игровой фильтр"
          value: root.ready ? (root.svc.settings.game || "off") : "off"
          options: [{ value: "off", label: "Выключен" }, { value: "tcp", label: "TCP 1024–65535" },
                    { value: "udp", label: "UDP 1024–65535" }, { value: "all", label: "TCP и UDP" }]
          onChanged: function(v) { root.svc.setOption("game", v) }
        }
        Hint { Layout.fillWidth: true; text: "Обход для игр по IP-сетям (ipset). Нагружает сильнее: включайте, если игра не подключается." }
        Dropdown {
          Layout.fillWidth: true
          label: "IP-сети (ipset)"
          value: root.ready ? (root.svc.settings.ipset || "loaded") : "loaded"
          options: [{ value: "loaded", label: "По списку" }, { value: "none", label: "Выключено" }, { value: "any", label: "Любой IP" }]
          onChanged: function(v) { root.svc.setOption("ipset", v) }
        }
        Dropdown {
          Layout.fillWidth: true
          label: "Голос Discord"
          value: root.ready ? (root.svc.settings.voice || "compatible") : "compatible"
          options: [{ value: "compatible", label: "Совместимый" }, { value: "standard", label: "Стандартный" }, { value: "off", label: "Выключен" }]
          onChanged: function(v) { root.svc.setOption("voice", v) }
        }
        Hint {
          Layout.fillWidth: true
          text: {
            var v = root.ready ? (root.svc.settings.voice || "compatible") : "compatible"
            if (v === "standard") return "Стандартный — подмена нулями, звонки могут не работать"
            if (v === "off") return "Выключен — голосовой трафик идёт без подмены"
            return "Совместимый — мягкая подмена для звонков Discord"
          }
        }
      }

      Card {
        RowLayout {
          Layout.fillWidth: true
          HoverHandler { cursorShape: Qt.PointingHandCursor }
          TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: stp.showExtra = !stp.showExtra }
          Label { Layout.fillWidth: true; font.bold: true; text: (stp.showExtra ? "▾ " : "▸ ") + "Дополнительно" }
        }
        RowLayout {
          Layout.fillWidth: true
          visible: stp.showExtra && root.ready && (root.svc.settings.game || "off") !== "off"
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Label { text: "Порты TCP" }
            TextField {
              Layout.fillWidth: true
              text: root.ready ? (root.svc.settings.gameTcp || "") : ""
              placeholderText: "например 1024-65535"
              onEditingFinished: root.svc.setOption("gametcp", text)
            }
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Label { text: "Порты UDP" }
            TextField {
              Layout.fillWidth: true
              text: root.ready ? (root.svc.settings.gameUdp || "") : ""
              placeholderText: "например 1024-65535"
              onEditingFinished: root.svc.setOption("gameudp", text)
            }
          }
        }
        Dropdown {
          Layout.fillWidth: true
          visible: stp.showExtra
          label: "Фейк для голоса Discord"
          value: root.ready ? (root.svc.settings.discordFake || "default") : "default"
          options: (root.ready && root.svc.fakeChoices ? root.svc.fakeChoices : ["default"]).map(function(n) {
            return { value: n, label: n === "default" ? "По умолчанию" : String(n).replace(/^fs_/, "").replace(/_/g, " ") }
          })
          onChanged: function(v) { root.svc.setOption("discordfake", v) }
        }
        Dropdown {
          Layout.fillWidth: true
          visible: stp.showExtra
          label: "Фейк для игр"
          value: root.ready ? (root.svc.settings.gameFake || "default") : "default"
          options: (root.ready && root.svc.fakeChoices ? root.svc.fakeChoices : ["default"]).map(function(n) {
            return { value: n, label: n === "default" ? "По умолчанию" : String(n).replace(/^fs_/, "").replace(/_/g, " ") }
          })
          onChanged: function(v) { root.svc.setOption("gamefake", v) }
        }
      }

      Card {
        RowLayout {
          Layout.fillWidth: true
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label { Layout.fillWidth: true; font.bold: true; text: "Hosts Flowseal" }
            Hint { Layout.fillWidth: true; text: "Добавляет в /etc/hosts адреса Discord-серверов из репозитория Flowseal, нужен пароль" }
          }
          ToggleSwitch {
            checked: root.ready && root.svc.hostsOn === true
            busy: root.ready && root.svc.busy
            onToggled: {
              if (!root.svc.hostsOn && !stp.hostsConfirm) { stp.hostsConfirm = true; hostsTimer.restart() }
              else root.svc.hostsSet(!root.svc.hostsOn)
            }
          }
        }
        RowLayout {
          Layout.fillWidth: true
          visible: stp.hostsConfirm && !(root.ready && root.svc.hostsOn)
          Hint { Layout.fillWidth: true; text: "Изменит /etc/hosts, нужен пароль" }
          Button { bordered: true; text: "Включить"; onClicked: { stp.hostsConfirm = false; hostsTimer.stop(); root.svc.hostsSet(true) } }
          Button { text: "Отмена"; onClicked: { stp.hostsConfirm = false; hostsTimer.stop() } }
        }
      }

      Card {
        RowLayout {
          Layout.fillWidth: true
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label { Layout.fillWidth: true; font.bold: true; text: "Discord" }
            Hint { Layout.fillWidth: true; text: "Помогает, если Discord не грузится после включения обхода; закройте Discord перед очисткой" }
          }
          Button { bordered: true; text: "Очистить кэш Discord"; onClicked: root.svc.clearDiscordCache() }
        }
      }

      Card {
        Label { font.bold: true; text: "Горячие клавиши" }
        Hint {
          Layout.fillWidth: true
          text: "Добавьте в ~/.config/hypr/bindings.lua, например:"
        }
        RowLayout {
          Layout.fillWidth: true
          TextField {
            id: hotkeyApp
            Layout.fillWidth: true
            readOnly: true
            selectByMouse: true
            text: "omarchy-shell krieziey.omarchy-zapret2 toggle"
          }
          Button { bordered: true; text: "Скопировать"; onClicked: Quickshell.execDetached(["wl-copy", hotkeyApp.text]) }
        }
        RowLayout {
          Layout.fillWidth: true
          TextField {
            id: hotkeyBypass
            Layout.fillWidth: true
            readOnly: true
            selectByMouse: true
            text: "omarchy-shell krieziey.omarchy-zapret2 toggleBypass"
          }
          Button { bordered: true; text: "Скопировать"; onClicked: Quickshell.execDetached(["wl-copy", hotkeyBypass.text]) }
        }
        Hint {
          Layout.fillWidth: true
          text: "Первая команда — окно приложения, вторая — включить/выключить обход"
        }
      }
    }
  }
}
