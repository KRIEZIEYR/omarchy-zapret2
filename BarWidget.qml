import QtQuick
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
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color bad: Model.pickBad(Color.urgent, Color.popups.background, "#e06c75")

  function findService() {
    if (svc) return
    var sh = root.bar && root.bar.shell ? root.bar.shell : null
    if (sh && typeof sh.serviceFor === "function") svc = sh.serviceFor(pluginId)
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
    dimmed: !root.ready || !root.svc.isOn
    tooltipText: !root.ready ? "Zapret2 загружается…"
        : (root.svc.errorText !== "" ? "󰀦 " + root.svc.errorText + "\n" : "")
          + root.svc.summary + "\nПКМ: " + (root.svc.isOn ? "выключить" : "включить") + " · СКМ: приложение"
    iconComponent: Component {
      Item {
        ZapretIcon {
          anchors.centerIn: parent
          iconSize: Style.space(14)
          color: root.barForeground
          filled: root.ready && root.svc.isOn
          warning: root.ready && (root.svc.bypassState === "error" || root.svc.errorText !== "")
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
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: strategy.popupOpen
      onCloseRequested: root.close()
      onActivateRequested: if (root.ready) root.svc.toggle()
      onTextKey: function(t) {
        if (!root.ready) return
        if (t === "t") root.svc.toggle()
        else if (t === "c") root.svc.runCheck()
        else if (t === "o") { root.close(); root.svc.openApp() }
        else if (t === "s") strategy.open()
      }

      ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

        // header: icon, name, state, switch
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)
          ZapretIcon {
            iconSize: Style.space(22)
            color: root.ready && root.svc.bypassState === "error" ? root.bad : root.fg
            filled: root.ready && root.svc.isOn
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
              Layout.fillWidth: true
              text: "Zapret2"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: !root.ready ? "Загрузка…"
                  : root.svc.busy ? "Выполняется: " + root.svc.busyLabel + "…"
                  : Model.stateText(root.svc.st) + (root.svc.installed && root.svc.isOn && root.svc.preset ? " · стратегия " + Model.presetTitle(root.svc.preset) : "")
              color: root.ready && root.svc.bypassState === "error" ? root.bad : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          ToggleSwitch {
            visible: root.ready && root.svc.installed
            checked: root.ready && root.svc.isOn
            busy: root.ready && root.svc.busy
            onToggled: root.svc.toggle()
          }
        }

        Text {
          Layout.fillWidth: true
          visible: text !== ""
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: !root.ready ? "" : root.svc.errorText !== "" ? root.svc.errorText : root.svc.flashText
          color: root.ready && root.svc.errorText !== "" ? root.bad : root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // first run
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.ready && root.svc.reachable && !root.svc.installed
          spacing: Style.space(8)
          Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "Движок zapret2 ещё не установлен. Установка скачает официальный релиз bol-van/zapret2, проверит sha256 и один раз спросит пароль."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Button {
            Layout.fillWidth: true
            bordered: true
            text: root.ready && root.svc.busy ? "Установка…" : "Установить"
            onClicked: root.svc.setup()
          }
        }

        // strategy
        Dropdown {
          id: strategy
          Layout.fillWidth: true
          visible: root.ready && root.svc.installed
          label: "Стратегия"
          value: root.ready ? root.svc.preset : ""
          options: {
            if (!root.ready) return []
            return Model.popupPresets(root.svc.presets, root.svc.autopickResult, root.svc.preset).map(function(n) {
              var nm = typeof n === "string" ? n : (n && n.name)
              return { value: nm, label: Model.presetTitle(nm) }
            })
          }
          onChanged: function(v) { if (v !== root.svc.preset) root.svc.setOption("preset", v) }
        }

        // last check
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.ready && root.svc.installed
          spacing: Style.space(4)
          RowLayout {
            Layout.fillWidth: true
            PanelSectionHeader { text: "Доступность"; Layout.fillWidth: true }
            Text {
              text: root.ready ? Model.ago(root.svc.check.time) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
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
                color: modelData.good ? root.fg : root.bad
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: !modelData.good
              }
              Text {
                text: modelData.ok + "/" + modelData.total
                color: modelData.good ? root.fg : root.bad
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
          Layout.fillWidth: true
          spacing: Style.space(6)
          Button {
            Layout.fillWidth: true
            visible: root.ready && root.svc.installed
            bordered: true
            text: "Проверить"
            tooltipText: "c"
            onClicked: root.svc.runCheck()
          }
          Button {
            Layout.fillWidth: true
            bordered: true
            text: "Приложение"
            tooltipText: "o"
            onClicked: { root.close(); root.svc.openApp() }
          }
        }
      }
    }
  }
}
