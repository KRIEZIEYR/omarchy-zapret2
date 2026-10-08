import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "model/Zapret.js" as Model

/*
 * Bar icon plus a quick popup: on/off, strategy, last check, and a way into
 * the full app. State lives in the plugin's service (Service.qml), shared
 * with the app window.
 */
Panel {
  id: root
  moduleName: "krieziey.omarchy-zapret2"
  ipcTarget: ""
  manageIpc: false

  readonly property string pluginId: "krieziey.omarchy-zapret2"
  property var svc: null
  readonly property bool ready: svc !== null
  readonly property string fontFamily: Style.font.family
  readonly property color fg: Color.popups.text
  readonly property color bg: Color.popups.background
  // Mixed toward the background, not darkened: Qt.darker collapses on a light
  // theme. Same helper the app window uses.
  readonly property color dim: Model.mixColor(root.fg, root.bg, 0.34)
  readonly property color errorColor: {
    var u = Color.urgent
    return u.hslSaturation < 0.2 ? fg : u
  }
  readonly property int ctlHeight: Style.spacing.controlHeight

  component PanelDropdown: Dropdown {
    id: pd
    property real closedAt: 0
    onPopupOpenChanged: if (!popupOpen) closedAt = Date.now()
    MouseArea {
      z: 10
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: pd.rowHeight
      cursorShape: Qt.PointingHandCursor
      onClicked: if (Date.now() - pd.closedAt > 300) pd.open()
    }
  }

  // One cursor walks the interactive controls (hero switch, install,
  // strategy, check, open); mouse hover joins the same model so there is a
  // single highlight. `?` toggles the legend, which otherwise stays put.
  property bool cursorActive: false
  property string cursorRow: ""
  property bool keysUsed: false
  property bool keyboardUser: false
  property bool legendHidden: false
  onKeysUsedChanged: if (keysUsed) keyboardUser = true

  readonly property bool firstRun: root.ready && root.svc.reachable && !root.svc.installed
  // Pinned status slot: running action, else the last error, else a note.
  readonly property string statusKind: {
    if (!root.ready) return "none"
    if (root.svc.busy) return "action"
    if (root.svc.errorText !== "") return "error"
    if (root.svc.flashText !== "") return "flash"
    return "none"
  }
  // Keyboard-only hint for the control under the cursor (mirrors tooltips).
  readonly property string hintText: {
    if (!root.cursorActive) return ""
    if (root.cursorRow === "hero") return root.ready && root.svc.isOn ? "Enter выключит обход" : "Enter включит обход"
    if (root.cursorRow === "install") return "Enter установит движок"
    if (root.cursorRow === "strategy") return "Enter откроет список · h/l тоже открывает"
    if (root.cursorRow === "check") return "Enter проверит доступность (c)"
    if (root.cursorRow === "open") return "Enter откроет приложение (o)"
    return ""
  }

  function findService() {
    if (svc) return
    var sh = root.bar && root.bar.shell ? root.bar.shell : null
    if (sh && typeof sh.serviceFor === "function") svc = sh.serviceFor(pluginId)
  }

  // Popup strategy label with the autopick score. Prefers the shared
  // Model.presetLabel(name, row, isBest, worse, tied) helper when the
  // model lane provides it; falls back to local formatting so the popup
  // keeps working when autopick data is missing.
  function presetLabelFallback(nm, r, isBest, worse, tied) {
    var title = Model.presetTitle(nm)
    if (!r || (r.total | 0) === 0) return title
    var s = title + " · " + r.score + "/" + r.total
    if (isBest && !tied) s += " · лучшая"
    if (worse) s += " · ⚠"
    return s
  }

  function staleStatus() {
    if (!root.ready) return { text: "", severity: "none" }
    return Model.staleStatus(root.svc.check, Date.now() / 1000)
  }

  // One status line for the popup: the explicit mismatch sentence when the
  // last check belongs to another configuration, otherwise the check's age.
  function checkStatusText() {
    if (!root.ready) return ""
    var v = Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult)
    if (v && v.action === "check") return v.note
    var ss = root.staleStatus()
    if (ss.text !== "") return ss.text
    return (v && v.note) ? v.note : ""
  }

  function checkStatusSeverity() {
    if (!root.ready) return "none"
    return root.staleStatus().severity
  }

  function cursorRows() {
    var rows = ["hero"]
    if (root.ready) {
      if (root.firstRun) rows.push("install")
      if (root.svc.installed) rows.push("strategy")
      if (root.svc.installed) rows.push("check")
    }
    rows.push("open")
    return rows
  }

  function setCursor(row) {
    root.cursorActive = true
    root.cursorRow = row
  }

  function moveCursor(dy) {
    var rows = root.cursorRows()
    var i = rows.indexOf(root.cursorRow)
    if (i === -1) i = dy > 0 ? -1 : 0
    else i = (i + dy) % rows.length
    if (i < 0) i += rows.length
    root.cursorActive = true
    root.cursorRow = rows[i]
  }

  function jumpCursor(edge) {
    var rows = root.cursorRows()
    root.cursorActive = true
    root.cursorRow = edge === "end" ? rows[rows.length - 1] : rows[0]
  }

  function activateCursor() {
    if (!root.ready) return
    if (!root.cursorActive) {
      root.cursorActive = true
      if (root.cursorRow === "") root.cursorRow = "hero"
      return
    }
    var r = root.cursorRow === "" ? "hero" : root.cursorRow
    if (r === "hero") root.svc.toggle()
    else if (r === "install") root.svc.setup()
    else if (r === "strategy") strategy.toggle()
    else if (r === "check") root.svc.runCheck()
    else if (r === "open") { root.close(); root.svc.openApp() }
  }

  onBarChanged: findService()
  onOpenedChanged: {
    if (svc) svc.popupOpen = opened
    if (opened) {
      if (svc) svc.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Timer {
    interval: 500
    running: !root.ready
    repeat: true
    triggeredOnStart: true
    onTriggered: root.findService()
  }

  // The quick popup by hotkey: omarchy-shell krieziey.omarchy-zapret2-bar toggle
  IpcHandler {
    target: "krieziey.omarchy-zapret2-bar"
    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.close() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    dimmed: root.ready && root.svc.reachable && !root.svc.isOn
    tooltipText: !root.ready ? "Zapret2 загружается…"
        : (root.svc.errorText !== "" ? "󰀦 " + root.svc.errorText + "\n" : "")
          + root.svc.summary + "\nПКМ: " + (root.svc.isOn ? "выключить" : "включить") + " · СКМ: приложение"
    iconComponent: Component {
      Item {
        ZapretIcon {
          anchors.centerIn: parent
          iconSize: Style.space(14)
          color: root.barForeground
          // Outline at bar size: on/off reads from the button dimming, a
          // fill at 14px only blurs the shield.
          filled: false
          simple: true
          warning: root.ready && (!root.svc.reachable || root.svc.bypassState === "error" || root.svc.errorText !== "")
          SequentialAnimation on opacity {
            running: root.ready && root.svc.busy
            loops: 8
            alwaysRunToEnd: true
            NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
          }
        }
      }
    }
    onPressed: function(code) {
      if (!root.ready) return
      if (code === Qt.RightButton) root.svc.toggle()
      else if (code === Qt.MiddleButton) root.svc.openApp()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Tighter top and bottom; the sides keep the kit's popup padding below.
    padding: Style.space(8)
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      readonly property real sideInset: Math.max(0, Style.spacing.popupPadding - panel.padding)
      blocked: strategy.popupOpen
      anchors.fill: parent
      anchors.leftMargin: sideInset
      anchors.rightMargin: sideInset
      onMoveRequested: function(dx, dy) {
        root.keysUsed = true
        if (!root.cursorActive) {
          root.cursorActive = true
          if (root.cursorRow === "") root.cursorRow = "hero"
          return
        }
        if (dy !== 0) root.moveCursor(dy > 0 ? 1 : -1)
        else if (dx !== 0) {
          if (root.cursorRow === "strategy" && root.ready && root.svc.installed) strategy.toggle()
          else root.moveCursor(dx > 0 ? 1 : -1)
        }
      }
      // Enter with no cursor shows it first instead of doing nothing.
      onActivateRequested: { root.keysUsed = true; root.activateCursor() }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (!root.ready) return
        root.keysUsed = true
        if (t === "?") { root.legendHidden = !root.legendHidden; return }
        if (t === "t") root.svc.toggle()
        else if (t === "c") root.svc.runCheck()
        else if (t === "o") { root.close(); root.svc.openApp() }
        else if (t === "s") { if (root.svc.installed) strategy.open() }
      }

      Shortcut { sequence: "Home"; enabled: root.opened && !keyCatcher.blocked; onActivated: { root.keysUsed = true; root.jumpCursor("home") } }
      Shortcut { sequence: "End"; enabled: root.opened && !keyCatcher.blocked; onActivated: { root.keysUsed = true; root.jumpCursor("end") } }

      Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          title: "Zapret2"
          meta: !root.ready ? "Загрузка…"
              : Model.stateText(root.svc.st) + (root.svc.installed && root.svc.isOn && root.svc.preset ? " · стратегия " + Model.presetTitle(root.svc.preset) : "")
          foreground: root.fg
          fontFamily: root.fontFamily
          iconOpacity: root.ready && root.svc.isOn ? 1.0 : 0.5
          iconComponent: Component {
            Item {
              implicitWidth: heroIcon.width + Style.space(6)
              implicitHeight: heroIcon.height
              MouseArea { id: heroIconHover; anchors.fill: parent; hoverEnabled: true }
              PanelToolTip {
                visible: heroIconHover.containsMouse
                text: !root.ready ? "Zapret2 загружается…"
                    : root.svc.errorText !== "" ? root.svc.errorText
                    : root.svc.isOn ? "Обход включён · ЛКМ: выключить" : "Обход выключен · ЛКМ: включить"
                fontFamily: root.fontFamily
              }
              ZapretIcon {
                id: heroIcon
                anchors.centerIn: parent
                iconSize: Math.round(Style.font.display * 1.25)
                color: root.ready && root.svc.bypassState === "error" ? root.errorColor : root.fg
                filled: root.ready && root.svc.isOn
              }
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              id: powerSwitch
              visible: root.ready && root.svc.installed
              checked: root.ready && root.svc.isOn
              busy: root.ready && root.svc.busy
              hasCursor: root.cursorRow === "hero"
              foreground: root.fg
              onToggled: root.svc.toggle()
              onHovered: function(h) { if (h) root.setCursor("hero") }
              Accessible.role: Accessible.CheckBox
              Accessible.name: "Обход DPI, " + (root.ready && root.svc.isOn ? "включён" : "выключен")
              Accessible.checked: checked
              Accessible.focusable: true
              Accessible.focused: hasCursor

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: !root.ready ? "" : root.svc.busy ? "Выполняется: " + root.svc.busyLabel + "…"
                      : root.svc.errorText !== "" ? root.svc.errorText
                      : root.svc.isOn ? "Выключить (t)" : "Включить (t)"
                fontFamily: root.fontFamily
              }
            }
          }
        }

        // One status slot: the running action, else the last error (with a
        // way to the journal), else a transient note.
        RowLayout {
          visible: root.statusKind !== "none"
          width: parent.width
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            textFormat: Text.PlainText
            wrapMode: root.statusKind === "error" ? Text.WordWrap : Text.NoWrap
            elide: root.statusKind === "error" ? Text.ElideNone : Text.ElideRight
            text: !root.ready ? ""
                : root.statusKind === "action" ? "Выполняется: " + root.svc.busyLabel + "…"
                : root.statusKind === "error" ? "󰀦 " + root.svc.errorText : root.svc.flashText
            color: root.statusKind === "error" ? root.errorColor : root.statusKind === "flash" ? Color.accent : root.dim
            font.family: root.fontFamily
            font.pixelSize: root.statusKind === "error" ? Style.font.bodySmall : Style.font.caption
            Accessible.role: Accessible.StaticText
            Accessible.name: text
            onTextChanged: if (root.statusKind === "error" && text !== "") Accessible.announce("Ошибка: " + text)
          }

          Button {
            visible: root.statusKind === "error"
            Layout.alignment: Qt.AlignTop
            bordered: false
            fontSize: Style.font.caption
            text: "Журнал"
            tooltipText: "Открыть диагностику и журнал (вкладка Движок)"
            onClicked: { root.close(); root.svc.openApp(4) }
          }
        }

        // Keyboard users never see hover tooltips: the control under the
        // cursor explains itself here. Kept once the keyboard is in use, so
        // no row moves when the cursor crosses the controls.
        Text {
          width: parent.width
          visible: root.keyboardUser && text.trim() !== ""
          textFormat: Text.PlainText
          text: root.hintText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // first run
        ColumnLayout {
          width: parent.width
          visible: root.firstRun
          spacing: Style.space(8)
          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "Движок zapret2 ещё не установлен. Установка скачает официальный релиз bol-van/zapret2, проверит sha256 и один раз спросит пароль."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          // First run: installing is the popup's one filled action.
          BorderSurface {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: installBtn.implicitWidth + Style.space(24)
            implicitHeight: Math.max(installBtn.implicitHeight, root.ctlHeight)
            color: Style.selectedFillFor(root.fg, Color.accent)
            borderSpec: Border.controlSpec("selected", root.fg, Color.accent)
            radius: Style.cornerRadius
            Button {
              id: installBtn
              anchors.fill: parent
              bordered: false
              foreground: Style.selectedStateColor(root.fg, Color.accent)
              hasCursor: root.cursorRow === "install"
              text: root.ready && root.svc.busy ? "Установка…" : "Установить"
              tooltipText: "Установить движок zapret2 (t)"
              onClicked: root.svc.setup()
              onHovered: function(h) { if (h) root.setCursor("install") }
              Accessible.role: Accessible.Button
              Accessible.name: "Установить движок zapret2"
              Accessible.focusable: true
              Accessible.focused: hasCursor
            }
          }
        }

        // strategy
        PanelDropdown {
          id: strategy
          width: parent.width
          visible: root.ready && root.svc.installed
          // Constant label: the value already starts with the strategy name.
          label: "Стратегия"
          rowHeight: root.ctlHeight
          popupRowHeight: root.ctlHeight
          foreground: root.fg
          hasCursor: root.cursorRow === "strategy"
          value: root.ready ? root.svc.preset : ""
          options: {
            if (!root.ready) return []
            var rows = Model.autopickRows(root.svc.autopickResult)
            var base = -1
            for (var bi = 0; bi < rows.length; bi++) if (rows[bi].baseline) { base = rows[bi].score; break }
            var rowOf = function(name) {
              for (var k = 0; k < rows.length; k++) if (rows[k].preset === name) return rows[k]
              return null
            }
            // Build list: active preset first, then top autopick rows (up to 10 total before "__more")
            var listedNames = []
            function pushName(n) {
              if (n && listedNames.indexOf(n) === -1) listedNames.push(n)
            }
            pushName(root.svc.preset)
            var top = rows.filter(function(r) {
              return !r.baseline && (r.total | 0) > 0
            }).map(function(r) { return r.preset })
            if (top.length === 0) {
              var names = ((root.svc.presets || []).map(function(p) {
                return typeof p === "string" ? p : (p && p.name)
              }).filter(function(n) { return !!n }))
              top = names.slice(0, 10)
            }
            top.forEach(pushName)
            // Limit to 10 before the "__more" entry
            if (listedNames.length > 10) listedNames = listedNames.slice(0, 10)
            var listed = listedNames.map(function(nm) {
              var r = rowOf(nm)
              var isBest = !!(r && r.chosen)
              var worse = !!(r && !r.baseline && (r.total | 0) > 0 && base >= 0 && (r.score | 0) < base)
              var tied = !!(r && !r.baseline && (r.total | 0) > 0 && base >= 0 && (r.score | 0) === base)
              var label = (typeof Model.presetLabel === "function") ? Model.presetLabel(nm, r, isBest, worse, tied) : root.presetLabelFallback(nm, r, isBest, worse, tied)
              return { value: nm, label: label }
            })
            var total = root.svc.presets ? root.svc.presets.length : 0
            var rest = total - listed.length
            if (rest > 0) listed.push({ value: "__more", label: "Все стратегии (" + rest + ") — открыть приложение" })
            return listed
          }
          onChanged: function(v) {
            if (v === "__more") { root.close(); root.svc.openApp(1); return }
            if (v !== root.svc.preset) root.svc.setOption("preset", v)
          }
          onHovered: function(h) { if (h) root.setCursor("strategy") }
        }

        // last check
        ColumnLayout {
          width: parent.width
          visible: root.ready && root.svc.installed
          spacing: Style.space(4)
          RowLayout {
            Layout.fillWidth: true
            PanelSectionHeader { text: "Доступность"; Layout.fillWidth: true; foreground: root.fg; fontFamily: root.fontFamily }
            HoverHandler { id: statusHover }
            Text {
              id: statusText
              text: root.checkStatusText()
              color: root.checkStatusSeverity() === "error" ? root.errorColor : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              textFormat: Text.PlainText
              elide: Text.ElideRight
              Layout.maximumWidth: Style.space(200)
            }
            PanelToolTip {
              // The popup has no room for the explainer inline, so it is one
              // hover away instead of missing entirely.
              visible: statusHover.hovered && statusText.text !== ""
              text: Model.CHECK_EXPLAINER
              fontFamily: root.fontFamily
            }
          }
          Repeater {
            model: root.ready ? Model.categories(root.svc.check) : []
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              Text {
                Layout.fillWidth: true
                text: (modelData.good ? "✓ " : (modelData.ok > 0 ? "⚠ " : "✗ ")) + modelData.label
                color: modelData.good ? root.fg : root.errorColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: !modelData.good
              }
              Text {
                text: modelData.ok + "/" + modelData.total
                color: modelData.good ? root.fg : root.errorColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: !modelData.good
              }
            }
          }
          Text {
            visible: root.ready && Model.categories(root.svc.check).length === 0
            text: "Нажмите «Проверить», чтобы узнать, что открывается"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(6)
          // The popup's one filled action.
          BorderSurface {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: checkBtn.implicitWidth + Style.space(24)
            implicitHeight: Math.max(checkBtn.implicitHeight, root.ctlHeight)
            color: Style.selectedFillFor(root.fg, Color.accent)
            borderSpec: Border.controlSpec("selected", root.fg, Color.accent)
            radius: Style.cornerRadius
            visible: root.ready && root.svc.installed
            Button {
              id: checkBtn
              anchors.fill: parent
              bordered: false
              foreground: Style.selectedStateColor(root.fg, Color.accent)
              hasCursor: root.cursorRow === "check"
              text: "Проверить"
              tooltipText: "Проверить доступность (c)"
              onClicked: root.svc.runCheck()
              onHovered: function(h) { if (h) root.setCursor("check") }
              Accessible.role: Accessible.Button
              Accessible.name: "Проверить доступность"
              Accessible.focusable: true
              Accessible.focused: hasCursor
            }
          }
          Button {
            Layout.fillWidth: true
            bordered: false
            fontSize: Style.font.caption
            implicitHeight: root.ctlHeight
            hasCursor: root.cursorRow === "open"
            text: "Открыть"
            tooltipText: "Открыть приложение (o)"
            onClicked: { root.close(); root.svc.openApp() }
            onHovered: function(h) { if (h) root.setCursor("open") }
            Accessible.role: Accessible.Button
            Accessible.name: "Открыть приложение"
            Accessible.focusable: true
            Accessible.focused: hasCursor
          }
        }

        // Keys, pinned at the bottom. Shown once the keyboard is used; `?`
        // hides or shows them. Before that, the hero icon's tooltip has them.
        Column {
          visible: root.keyboardUser && !root.legendHidden
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: [["ПЕРЕХОД", "j/k строка · h/l действие · Enter применить · Home/End края"], ["КЛАВИШИ", "t вкл/выкл · c проверить · o открыть · s стратегия · ? скрыть"]]
            delegate: RowLayout {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                text: modelData[0]
                Layout.preferredWidth: Style.space(72)
                Layout.alignment: Qt.AlignTop
                foreground: root.fg
                fontFamily: root.fontFamily
              }
              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: modelData[1]
                wrapMode: Text.WordWrap
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }
}
