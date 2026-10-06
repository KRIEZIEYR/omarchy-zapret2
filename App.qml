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
  // Secondary text is mixed toward the background, never darkened: Qt.darker
  // only darkens and collapses on a light theme.
  readonly property color dim: Model.mixColor(root.fg, root.bg, 0.34)
  readonly property color dimmer: Model.mixColor(root.fg, root.bg, 0.5)
  readonly property color bad: Model.pickBad(Color.urgent, Color.popups.background, "#e06c75")

  readonly property bool sysUpdate: ready && svc.installed && !svc.appCurrent

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

  function handleEscape() {
    if (tab === 1) {
      if (spPg.showing) { spPg.showing = false; return }
      if (spPg.editing) { spPg.editing = false; return }
      if (spPg.selectedName !== "") { spPg.selectedName = ""; return }
    }
    if (tab === 5 && stpPg.hostsConfirm) { stpPg.hostsConfirm = false; return }
    if (tab === 4 && epPg.armRemove) { epPg.armRemove = false; return }
    if (tab === 0 && ovPg.cursorKey !== "") { ovPg.cursorKey = ""; return }
    root.dismiss()
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
    // Labels in fixed-width columns must stay on one line: a wrapped name
    // would push the row's other columns out of alignment.
    property bool fixedWidth: false
    wrapMode: fixedWidth ? Text.NoWrap : Text.Wrap
    elide: fixedWidth ? Text.ElideRight : Text.ElideNone
  }

  component Hint: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    property bool fixedWidth: false
    wrapMode: fixedWidth ? Text.NoWrap : Text.Wrap
    elide: fixedWidth ? Text.ElideRight : Text.ElideNone
  }

  component Card: BorderSurface {
    id: cardSurface
    default property alias content: inner.data
    property alias spacing: inner.spacing
    Layout.fillWidth: true
    implicitHeight: inner.implicitHeight + Style.space(24)
    color: Style.normalFillFor(root.fg, Color.accent)
    borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
    radius: Style.cornerRadius
    ColumnLayout {
      id: inner
      anchors.fill: parent
      anchors.leftMargin: cardSurface.contentLeftInset + Style.space(12)
      anchors.rightMargin: cardSurface.contentRightInset + Style.space(12)
      anchors.topMargin: cardSurface.contentTopInset + Style.space(12)
      anchors.bottomMargin: cardSurface.contentBottomInset + Style.space(12)
      spacing: Style.space(8)
    }
  }

  // The single filled action of a page or card. The kit Button keeps the text,
  // tooltip and keyboard behaviour; this wrapper supplies the accent fill.
  // `selected: true` is deliberately not used: in the kit it means "chosen"
  // and would paint the button like a nav row instead of an action.
  component PrimaryButton: BorderSurface {
    id: primary
    property string text: ""
    property string tooltipText: ""
    property color fg: root.fg
    signal clicked()
    implicitWidth: primaryBtn.implicitWidth + Style.space(24)
    implicitHeight: Math.max(primaryBtn.implicitHeight, Style.spacing.controlHeight)
    color: Style.selectedFillFor(primary.fg, Color.accent)
    borderSpec: Border.controlSpec("selected", primary.fg, Color.accent)
    radius: Style.cornerRadius
    Button {
      id: primaryBtn
      anchors.fill: parent
      bordered: false
      foreground: Style.selectedStateColor(primary.fg, Color.accent)
      text: primary.text
      tooltipText: primary.tooltipText
      onClicked: primary.clicked()
      Accessible.role: Accessible.Button
      Accessible.name: primary.text
    }
  }

  // Collapsible section header that is a real control: the kit Button gives it
  // focus, Enter/Space and a pointer cursor, which a header plus handlers does
  // not.
  component Disclosure: Button {
    id: disc
    property string caption: ""
    property bool expanded: false
    signal toggled()
    leftAlign: true
    bordered: false
    Layout.fillWidth: true
    text: (disc.expanded ? "▾ " : "▸ ") + disc.caption
    onClicked: disc.toggled()
    Accessible.role: Accessible.Button
    Accessible.name: disc.caption
    Accessible.expanded: disc.expanded
  }

  component PickRow: CursorSurface {
    id: pickRow
    required property var row
    property int baseScore: -1
    property bool selected: false
    signal picked(string preset)
    // Delta relative to the no-bypass baseline: 0 = база, −N worse, +N better.
    property int delta: (row && !row.baseline && baseScore >= 0 && ((row.total | 0) > 0)) ? ((row.score | 0) - baseScore) : 0
    property bool showDelta: !!row && !row.baseline && baseScore >= 0 && ((row.total | 0) > 0) && delta !== 0
    // The baseline is already the row's own leading number, so it is not
    // repeated here: repeating it is what pushed the delta into the ellipsis.
    property string summary: {
      if (row && row.error) return String(row.error)
      var s = ((row && row.score) || 0) + "/" + ((row && row.total) || 0)
      if (row && !row.baseline && baseScore >= 0 && (row.total | 0) > 0) {
        if ((row.score | 0) === baseScore) s += " · = без обхода"
        else if ((row.score | 0) < baseScore) s += " · хуже базы"
        else s += " · лучше базы"
      }
      return s
    }
    foreground: root.fg
    Layout.fillWidth: true
    implicitHeight: pickInner.implicitHeight + Style.space(14)
    hasCursor: pickHover.hovered || selected
    current: !!(row && row.chosen)
    Accessible.role: Accessible.Button
    Accessible.name: ((row && row.title) || "") + ((row && row.chosen) ? ", выбрана" : "")
    HoverHandler { id: pickHover }
    TapHandler { onTapped: { if (row && !row.baseline && root.ready && !root.svc.busy) root.svc.setOption("preset", row.preset) } }
    RowLayout {
      id: pickInner
      anchors.fill: parent
      anchors.margins: Style.space(7)
      spacing: Style.space(8)
      Label {
        Layout.preferredWidth: Style.space(160)
        fixedWidth: true
        text: ((row && row.chosen) ? "● " : "") + ((row && row.title) || "")
        font.bold: !!(row && row.chosen)
      }
      Rectangle {
        Layout.fillWidth: true
        Layout.minimumWidth: Style.space(90)
        visible: showDelta
        height: Style.space(6)
        radius: height / 2
        color: Style.normalFillFor(root.fg, Color.accent)
        Rectangle {
          width: 2
          height: parent.height
          x: (parent.width - width) / 2
          color: root.dim
        }
        Rectangle {
          height: parent.height
          radius: parent.radius
          color: delta < 0 ? root.bad : Color.accent
          width: Math.min(parent.width / 2, parent.width / 2 * Math.abs(delta) / Math.max(1, ((row && row.total) || 14)))
          x: delta < 0 ? parent.width / 2 - width : parent.width / 2
        }
      }
      Label {
        Layout.preferredWidth: Style.space(38)
        fixedWidth: true
        visible: showDelta
        horizontalAlignment: Text.AlignRight
        color: delta < 0 ? root.bad : Color.accent
        font.bold: true
        text: (delta > 0 ? "+" : "−") + Math.abs(delta)
      }
      Hint {
        Layout.preferredWidth: Style.space(168)
        fixedWidth: true
        text: pickRow.summary
      }
      // The width is reserved so the bar never resizes when "Применить"
      // appears under the pointer.
      Item {
        Layout.preferredWidth: Style.space(96)
        Layout.fillHeight: true
        Button {
          anchors.fill: parent
          bordered: true
          visible: !!row && !row.baseline && (pickHover.hovered || hasCursor || selected || (row && row.chosen)) && (!root.ready || root.svc.preset !== row.preset)
          enabled: !!row && !row.baseline && root.ready && !root.svc.busy && root.svc.preset !== row.preset
          text: "Применить"
          tooltipText: "Применить " + ((row && row.title) || (row && row.preset) || "")
          onClicked: { root.svc.setOption("preset", row.preset) }
        }
      }
    }
    PanelToolTip {
      visible: pickHover.hovered && !!row && !row.baseline
      text: ((row && row.title) || (row && row.preset) || "") + ((row && row.chosen) ? " · выбрана" : " · нажмите, чтобы применить")
      fontFamily: root.fontFamily
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
    // Editors do not wrap, so long lines need a scrollbar instead of being
    // silently clipped at the card edge.
    contentWidth: Math.max(availableWidth, area.implicitWidth)
    background: BorderSurface {
      color: Style.normalFillFor(root.fg, Color.accent)
      borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
      radius: Style.cornerRadius
    }
    TextArea {
      id: area
      color: root.fg
      placeholderTextColor: root.dimmer
      font.family: root.monoFamily
      font.pixelSize: Style.font.bodySmall
      selectByMouse: true
      wrapMode: TextEdit.NoWrap
      selectionColor: Style.selectionFillFor(root.fg, Color.accent)
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
    // The shell may offer more room than the content can use; capping the
    // window keeps pages from turning into a column of cards over 60% void.
    maximumWidth: Style.space(1280)
    maximumHeight: Style.space(820)
    // closed by the window manager (Super+W, close button): tell the shell
    onVisibleChanged: if (!visible && !root.closingFromHost) root.dismiss()

    Item {
      id: keyCtrl
      anchors.fill: parent
      Keys.onPressed: function(e) {
        if ((e.modifiers & Qt.ControlModifier) && e.key >= Qt.Key_1 && e.key <= Qt.Key_6) {
          root.tab = e.key - Qt.Key_1
          e.accepted = true
        } else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_T && root.ready) {
          root.svc.toggle()
          e.accepted = true
        }
      }

      PanelKeyCatcher {
        id: appKeys
        anchors.fill: parent
        blocked: (root.tab === 1 && spPg.uiBlocked) || (root.tab === 2 && lpPg.uiBlocked)
            || (root.tab === 3 && sePg.uiBlocked) || (root.tab === 4 && epPg.uiBlocked)
            || (root.tab === 5 && stpPg.uiBlocked)
        onMoveRequested: function(dx, dy) {
          if (dy === 0) return
          if (root.tab === 0) ovPg.moveCursor(dy)
          else if (root.tab === 1) spPg.moveCursor(dy)
        }
        onActivateRequested: {
          if (root.tab === 0) ovPg.activateCursor()
          else if (root.tab === 1) spPg.activateCursor()
        }
        onCloseRequested: root.handleEscape()
        onTextKey: function(t) {
          if (t.length !== 1) return
          var code = t.charCodeAt(0)
          if (code < 32 || code === 127) return
          if (t === "/" && root.tab === 1) spPg.focusFilter()
          else if (t === "/" && root.tab === 3) sePg.focusDomains()
        }

      Rectangle {
        id: card
        anchors.fill: parent
        color: root.bg
        // Clicking the background returns the keyboard to the page, but never
        // steals it from a field the user is typing in.
        MouseArea {
          anchors.fill: parent
          onClicked: if (!appKeys.blocked) appKeys.forceActiveFocus()
        }

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.space(16)
          spacing: Style.space(16)

          // sidebar
          ColumnLayout {
            Layout.preferredWidth: Style.space(170)
            Layout.fillHeight: true
            spacing: Style.space(6)

            PanelHero {
              Layout.fillWidth: true
              Layout.bottomMargin: Style.space(10)
              foreground: root.fg
              fontFamily: root.fontFamily
              iconOpacity: root.ready && root.svc.isOn ? 1.0 : 0.6
              iconComponent: Component {
                ZapretIcon {
                  iconSize: Style.space(28)
                  color: root.ready && root.svc.bypassState === "error" ? root.bad : root.fg
                  filled: root.ready && root.svc.isOn
                  warning: root.ready && root.svc.errorText !== ""
                }
              }
              title: "Zapret2"
              meta: root.ready ? (root.svc.bypassState === "error" ? Model.stateText(root.svc.st) : (root.svc.isOn ? "Включён" : "Выключен")) : "Загрузка…"
            }

            Repeater {
              model: root.tabs
              delegate: RowLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: Style.space(6)
                Label {
                  Layout.preferredWidth: Style.space(12)
                  fixedWidth: true
                  horizontalAlignment: Text.AlignRight
                  color: root.dim
                  text: String(index + 1)
                }
                Button {
                  Layout.fillWidth: true
                  leftAlign: true
                  text: modelData
                  selected: root.tab === index
                  tooltipText: "Ctrl+" + (index + 1) + (index === 4 && root.sysUpdate ? " · есть обновление" : "")
                  onClicked: root.tab = index
                }
                // A quiet badge, not a chip: the update is a status, and it
                // stays visible on every tab, including Обзор.
                BorderSurface {
                  Layout.alignment: Qt.AlignVCenter
                  visible: index === 4 && root.ready && root.svc.installed && !root.svc.appCurrent
                  implicitWidth: pillText.implicitWidth + Style.space(8)
                  implicitHeight: pillText.implicitHeight + Style.space(2)
                  color: "transparent"
                  borderSpec: Border.flat(root.dim, 1)
                  radius: Style.cornerRadius
                  Text {
                    id: pillText
                    anchors.centerIn: parent
                    text: "обновление"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            Item { Layout.fillHeight: true }

            Hint {
              Layout.fillWidth: true
              text: "Ctrl+1…6 — вкладки\nCtrl+T — вкл/выкл\n/ — поиск"
            }
            Hint {
              Layout.fillWidth: true
              visible: root.ready && root.svc.busy
              text: root.ready ? "Выполняется: " + root.svc.busyLabel + "…" : ""
            }
          }

          Rectangle { Layout.fillHeight: true; width: 1; color: Border.color(Border.controlSpec("normal", root.fg, Color.accent)) }

          // content
          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.space(10)

            RowLayout {
              Layout.fillWidth: true
              // The slot is always reserved: a status line that appears and
              // disappears must not shove the whole page down.
              Layout.minimumHeight: Style.space(22)
              visible: root.ready && (root.svc.errorText !== "" || root.svc.flashText !== "")
              spacing: Style.space(8)
              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: !root.ready ? "" : root.svc.errorText !== "" ? "󰀦 " + root.svc.errorText : root.svc.flashText
                color: root.ready && root.svc.errorText !== "" ? root.bad : Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                Accessible.role: Accessible.StaticText
                Accessible.name: text
              }
              Button {
                bordered: true
                visible: root.ready && root.svc.errorText !== ""
                text: "Диагностика"
                tooltipText: "Открыть Движок: диагностика и журнал"
                onClicked: root.tab = 4
              }
            }

            Card {
              visible: root.ready && root.svc.reachable && !root.svc.installed
              PanelSectionHeader { Layout.fillWidth: true; text: "Движок zapret2 не установлен"; foreground: root.fg; fontFamily: root.fontFamily }
              Hint {
                Layout.fillWidth: true
                text: "Установка скачает последний релиз bol-van/zapret2 с GitHub, сверит sha256 и разложит файлы в /opt/omarchy-zapret2 (root). "
                    + "Пароль спросят один раз. Дальше включение, стратегии, списки и blockcheck2 работают без пароля."
              }
              Button { bordered: true; text: root.ready && root.svc.busy ? "Установка…" : "Установить"; tooltipText: "Установить движок zapret2"; onClicked: root.svc.setup() }
            }

            StackLayout {
              Layout.fillWidth: true
              Layout.fillHeight: true
              currentIndex: root.tab

              OverviewPage { id: ovPg }
              StrategiesPage { id: spPg }
              ListsPage { id: lpPg }
              SearchPage { id: sePg }
              EnginePage { id: epPg }
              SettingsPage { id: stpPg }
            }
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
    property string cursorKey: ""
    readonly property bool uiBlocked: false
    function catKeys() {
      if (!root.ready) return []
      return Model.categories(root.svc.check).map(function(c) { return c.key })
    }
    function moveCursor(dy) {
      var keys = ov.catKeys()
      if (ov.cursorKey === "") { ov.cursorKey = dy > 0 ? "hero" : (keys.length > 0 ? keys[keys.length - 1] : "hero"); return }
      if (ov.cursorKey === "hero") {
        if (dy > 0 && keys.length > 0) ov.cursorKey = keys[0]
        return
      }
      var i = keys.indexOf(ov.cursorKey)
      if (i === -1) { ov.cursorKey = "hero"; return }
      var n = i + dy
      if (n < 0) ov.cursorKey = "hero"
      else if (n < keys.length) ov.cursorKey = keys[n]
    }
    function activateCursor() {
      if (!root.ready) return
      if (ov.cursorKey === "hero") { root.svc.toggle(); return }
      if (ov.cursorKey !== "") {
        var e = Object.assign({}, ov.expanded)
        e[ov.cursorKey] = !e[ov.cursorKey]
        ov.expanded = e
      }
    }
    clip: true
    contentWidth: availableWidth
    ColumnLayout {
      width: parent.width
      spacing: Style.space(12)

      // The plugin update has one action and one name: this notice on Обзор
      // and a labelled button on the Движок diagnostics row.
      Card {
        visible: root.sysUpdate
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            PanelSectionHeader { Layout.fillWidth: true; text: "Доступно обновление Zapret2"; foreground: root.fg; fontFamily: root.fontFamily }
            Hint { Layout.fillWidth: true; text: "Обновит системную часть плагина и спросит пароль. Настройки, списки и стратегии останутся." }
          }
          Button {
            bordered: true
            enabled: root.ready && !root.svc.busy
            text: "Обновить плагин"
            tooltipText: "Установить обновление системной части плагина (спросит пароль)"
            onClicked: root.svc.updateApp()
          }
        }
      }

      Card {
        id: headCard
        // One verdict object drives the whole card: `action === "check"` is the
        // explicit "this check belongs to another configuration" case, so the
        // card never has to guess from Russian substrings.
        readonly property var info: root.ready ? Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult) : null
        readonly property var staleStatus: root.ready ? Model.staleStatus(root.svc.check) : ({ text: "", severity: "none" })
        property bool isMismatch: !!headCard.info && headCard.info.action === "check"
        property bool isStaleError: headCard.staleStatus.severity === "error"
        property bool isNeutral: !!headCard.info && headCard.info.tone === "neutral" && headCard.info.action === "none"
        PanelHero {
          Layout.fillWidth: true
          foreground: root.fg
          fontFamily: root.fontFamily
          iconOpacity: root.ready && root.svc.isOn ? 1.0 : 0.6
          iconComponent: Component {
            ZapretIcon {
              iconSize: Style.space(28)
              color: root.ready && root.svc.bypassState === "error" ? root.bad : root.fg
              filled: root.ready && root.svc.isOn
              warning: false
            }
          }
          title: {
            if (!root.ready) return ""
            if (root.svc.bypassState === "error") return Model.stateText(root.svc.st)
            return root.svc.isOn ? "Включён" : "Выключен"
          }
          meta: !root.ready || !root.svc.installed ? "" : "движок " + (root.svc.st.engine || "?") + (root.svc.st.restarts > 0 ? " · перезапусков " + root.svc.st.restarts : "")
          trailingControl: Component {
            ToggleSwitch {
              id: heroSwitch
              enabled: root.ready && root.svc.installed
              checked: root.ready && root.svc.isOn
              busy: root.ready && root.svc.busy
              foreground: root.fg
              hasCursor: ov.cursorKey === "hero"
              onHovered: function(h) { if (h) ov.cursorKey = "hero" }
              onToggled: root.svc.toggle()
              Accessible.role: Accessible.CheckBox
              Accessible.name: "Обход, " + (root.ready && root.svc.isOn ? "включён" : "выключен")
              Accessible.checked: checked
              PanelToolTip {
                visible: heroSwitch.containsMouse
                text: root.ready && root.svc.isOn ? "Выключить обход (Ctrl+T)" : "Включить обход (Ctrl+T)"
                fontFamily: root.fontFamily
              }
            }
          }
        }
        Label {
          Layout.fillWidth: true
          visible: root.ready && root.svc.installed && !headCard.isNeutral
          fixedWidth: true
          // The power state is already the hero's title; this line only says
          // which strategy is loaded.
          text: {
            if (!root.ready) return ""
            return "Стратегия: " + (Model.presetTitle(root.svc.preset) || "—")
          }
        }
        Text {
          Layout.fillWidth: true
          visible: text !== ""
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: headCard.isNeutral
          text: {
            if (!root.ready || !headCard.info) return ""
            if (headCard.isNeutral) return "✓ " + root.fixQuic(headCard.info.text)
            return root.fixQuic(headCard.info.text)
          }
          color: {
            if (!root.ready || !headCard.info) return Color.popups.text
            if (headCard.isNeutral) return Color.accent
            if (headCard.info.tone === "good") return Color.accent
            if (headCard.info.tone === "error" || headCard.info.tone === "bad") return root.bad
            return Color.popups.text
          }
        }
        Hint {
          Layout.fillWidth: true
          visible: text !== ""
          color: headCard.isStaleError ? root.bad : root.dim
          text: {
            if (!root.ready || !headCard.info) return ""
            // The mismatch sentence names both sides; the age is the fallback.
            if (headCard.isMismatch) return headCard.info.note
            if (headCard.staleStatus.text !== "") return headCard.staleStatus.text
            if (headCard.isNeutral) {
              var n = headCard.info.note || ""
              return n !== "" ? n + " · " + Model.NOT_NEEDED_EXPL : Model.NOT_NEEDED_EXPL
            }
            return headCard.info.note || ""
          }
        }
        RowLayout {
          Layout.fillWidth: true
          visible: root.ready && root.svc.installed
          spacing: Style.space(8)
          Button {
            bordered: true
            enabled: root.ready && root.svc.installed && !root.svc.busy
            text: "Проверить"
            tooltipText: "Проверить доступность с текущей стратегией"
            onClicked: root.svc.runCheck()
          }
          // The filled action of this page. Emphasis never depends on data.
          PrimaryButton {
            enabled: root.ready && root.svc.installed && !root.svc.busy
            text: root.ready && root.svc.isOn ? "Выключить обход" : "Включить обход"
            tooltipText: headCard.isMismatch ? "Включить обход без новой проверки"
                : headCard.isNeutral ? "Проверка показывает, что обход не нужен — включить принудительно"
                : "Включить обход (Ctrl+T)"
            onClicked: {
              if (root.svc.isOn) root.svc.turnOff()
              else root.svc.turnOn()
            }
          }
        }
      }

      Card {
        visible: root.ready && root.svc.installed
        id: availCard
        readonly property var staleStatus: root.ready ? Model.staleStatus(root.svc.check) : ({ text: "", severity: "none" })
        property bool staleError: staleStatus.severity === "error"
        property bool showExplainer: false
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          PanelSectionHeader { text: "Доступность"; foreground: root.fg; fontFamily: root.fontFamily }
          PanelActionButton {
            iconText: "?"
            tooltipText: "Что означают проверки"
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: availCard.showExplainer = !availCard.showExplainer
          }
          Item { Layout.fillWidth: true }
          Hint {
            color: availCard.staleError ? root.bad : root.dim
            text: availCard.staleStatus.text
          }
        }
        Hint {
          Layout.fillWidth: true
          visible: availCard.showExplainer
          text: Model.CHECK_EXPLAINER
        }
        Repeater {
          model: root.ready ? Model.categories(root.svc.check) : []
          delegate: ColumnLayout {
            required property var modelData
            property string catKey: modelData.key
            property bool catQuic: !modelData.good && root.ready && Model.isQuicOnlyCat(root.svc.check, modelData.key)
            Layout.fillWidth: true
            spacing: Style.space(2)
            CursorSurface {
              Layout.fillWidth: true
              implicitHeight: catHead.implicitHeight + Style.space(8)
              foreground: root.fg
              hasCursor: ov.cursorKey === catKey
              Accessible.role: Accessible.Button
              Accessible.name: modelData.label + ", " + modelData.ok + " из " + modelData.total
              HoverHandler {
                onHoveredChanged: if (hovered) ov.cursorKey = catKey
              }
              TapHandler {
                onTapped: {
                  ov.cursorKey = catKey
                  var e = Object.assign({}, ov.expanded)
                  e[catKey] = !e[catKey]
                  ov.expanded = e
                }
              }
              RowLayout {
                id: catHead
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)
                Label {
                  Layout.fillWidth: true
                  Layout.minimumWidth: Style.space(120)
                  fixedWidth: true
                  font.bold: !modelData.good
                  color: modelData.good ? root.fg : (catQuic ? root.fg : root.bad)
                  text: {
                    var open = !!ov.expanded[catKey]
                    var glyph = modelData.good ? "✓ " : (modelData.ok > 0 ? "⚠ " : "✗ ")
                    return (open ? "▾ " : "▸ ") + glyph + modelData.label
                  }
                }
                Label {
                  Layout.preferredWidth: Style.space(52)
                  fixedWidth: true
                  horizontalAlignment: Text.AlignRight
                  font.bold: !modelData.good
                  color: modelData.good ? root.fg : (catQuic ? root.fg : root.bad)
                  text: modelData.ok + "/" + modelData.total
                }
                // One reason per row, right of an aligned count, instead of a
                // single long sentence with the count buried in it.
                Hint {
                  Layout.fillWidth: true
                  fixedWidth: true
                  color: catQuic ? root.fg : root.dim
                  text: {
                    var hosts = (root.ready && root.svc.check.categories[modelData.key]) ? root.svc.check.categories[modelData.key].results : []
                    var failed = hosts.filter(function(h) { return !h.ok })
                    if (failed.length === 0) return ""
                    var quicOnly = failed.every(function(h) { return h.http3 })
                    return quicOnly ? Model.quicWarning() : Model.curlError(failed[0].error)
                  }
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
                  color: modelData.ok ? root.dim : (modelData.http3 ? root.fg : root.bad)
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
    property bool showAll: true
    property bool showAllInit: false
    property bool onlyGood: true
    property int hiddenWorseCount: 0
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
    onVisibleChanged: if (visible) { sp.ensureShowAll(); Qt.callLater(scrollToActive) }
    Component.onCompleted: { sp.ensureShowAll(); if (visible) Qt.callLater(scrollToActive) }

    function ensureShowAll() {
      if (sp.showAllInit || !root.ready) return
      sp.showAllInit = true
      var notNeeded = root.svc.autopickResult && root.svc.autopickResult.notNeeded === true
      if (notNeeded) sp.showAll = false
      else if (sp.totalPresets() > 40) sp.showAll = false
    }

    function focusFilter() { filterField.forceActiveFocus() }

    function edit(name) {
      editing = true
      editName = name ? name.replace(/^my-/, "") : ""
      editor.text = ""
      if (name) root.svc.loadText(["custom", "show", name], function(r) { if (r.ok) editor.text = r.data.text })
      else editor.text = "# Своя стратегия — секции nfqws2: [TCP_HTTP], [TCP_TLS], [TCP_GENERIC], [QUIC]\n"
          + "# Опции: --lua-desync, --payload, --out-range и др. (см. man nfqws2)\n"
          + "# Пример:\n"
          + "# [TCP_HTTP]\n"
          + "# --lua-desync=fake:blob=http_iana:tcp_md5:repeats=6\n"
          + "# --lua-desync=multisplit:pos=2,host+1\n"
          + "# [TCP_TLS]\n"
          + "# --lua-desync=fake:blob=tls_google:tcp_md5:repeats=6\n"
          + "# --lua-desync=multisplit:pos=2,midsld\n"
          + "# [TCP_GENERIC]\n"
          + "# --lua-desync=fake:blob=tls_google:tcp_md5:repeats=4\n"
          + "# --lua-desync=multisplit:pos=2\n"
          + "# [QUIC]\n"
          + "# --lua-desync=fake:blob=quic_google:repeats=6\n"
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
      if (!r) return "не проверялась"
      var bt = (typeof Model.breaksText === "function") ? Model.breaksText(r) : "не проверялась"
      if ((r.total | 0) <= 0) return r.error !== "" ? r.error : bt
      var s = r.score + "/" + r.total
      if (sp.isTied(sp.recommendedName())) return bt + " · " + s + " — как без обхода"
      return bt + " · " + s
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

    function isTied(name) {
      var r = pickRow(name)
      if (!r || r.baseline || (r.total | 0) === 0) return false
      var b = baseScore()
      return b >= 0 && r.score === b
    }

    function testedCount() {
      if (!root.ready || !root.svc.presets) return 0
      var n = 0
      for (var i = 0; i < root.svc.presets.length; i++) {
        if (sp.isTested(root.svc.presets[i].name)) n++
      }
      return n
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
      if ((r && (r.total | 0)) > 0 && t !== "не проверялась" && r.error === "") {
        var s = r.score + "/" + r.total
        if (t.indexOf(s) === -1) t += " · " + s
      }
      if (sp.isTied(p.name)) t += " — как без обхода"
      else if (sp.isWorse(p.name)) t += " · ⚠ хуже, чем без обхода"
      return t
    }

    function groups() {
      if (!root.ready) return []
      var order = []
      var per = {}
      var list = root.svc.presets.slice()
      var f = sp.filter.trim().toLowerCase()
      if (f !== "") {
        list = list.filter(function(p) {
          if (Model.presetTitle(p.name).toLowerCase().indexOf(f) !== -1) return true
          return sp.flowsealSource(p.name).toLowerCase().indexOf(f) !== -1
        })
      }
      var hiddenWorse = 0
      if (sp.onlyGood) {
        var before = list.length
        list = list.filter(function(p) {
          return !sp.isWorse(p.name)
        })
        hiddenWorse = before - list.length
      }
      sp.hiddenWorseCount = hiddenWorse
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
          var fa = ra && (ra.fails !== undefined) ? ra.fails : 999
          var fb = rb && (rb.fails !== undefined) ? rb.fails : 999
          if (typeof Model.failCount === "function") {
            if (ra) fa = Model.failCount(ra)
            if (rb) fb = Model.failCount(rb)
          }
          if (fa !== fb) return fa - fb
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
      scrollToName(root.svc.preset)
    }

    function flatNames() {
      var out = []
      var groups = sp.groups()
      for (var gi = 0; gi < groups.length; gi++) {
        var rows = sp.groupRows(groups[gi])
        for (var ri = 0; ri < rows.length; ri++) {
          if (rows[ri].name !== undefined && rows[ri].name !== "") out.push(rows[ri].name)
        }
      }
      return out
    }

    function moveCursor(dy) {
      var names = sp.flatNames()
      if (names.length === 0) return
      var i = names.indexOf(sp.selectedName)
      if (i === -1) { sp.selectedName = dy > 0 ? names[0] : names[names.length - 1] }
      else sp.selectedName = names[Math.max(0, Math.min(names.length - 1, i + dy))]
      if (sp.armDelete !== "" && sp.armDelete !== sp.selectedName) sp.armDelete = ""
      scrollToName(sp.selectedName)
    }

    function activateCursor() {
      if (!root.ready || sp.selectedName === "" || root.svc.busy) return
      root.svc.setOption("preset", sp.selectedName)
    }

    function scrollToName(name) {
      if (!name) return
      var groups = sp.groups()
      for (var gi = 0; gi < groups.length; gi++) {
        var rows = sp.groupRows(groups[gi])
        for (var ri = 0; ri < rows.length; ri++) {
          if (rows[ri].name !== "" && rows[ri].name === name) {
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
          if (un[ui].name === name) { sp.toggleMore(groups[gi].group); Qt.callLater(function() { scrollToName(name) }); return }
        }
      }
    }

    readonly property bool uiBlocked: (filterField.activeFocus || nameField.activeFocus
        || editor.area.activeFocus || viewerEditor.area.activeFocus)

    Card {
      id: recCard
      visible: !sp.editing && !sp.showing
      property bool notNeeded: root.ready && root.svc.autopickResult.notNeeded === true
      PanelSectionHeader { Layout.fillWidth: true; text: recCard.notNeeded ? "Рекомендация" : "Рекомендуемая"; foreground: root.fg; fontFamily: root.fontFamily }
      Label { Layout.fillWidth: true; fixedWidth: true; text: recCard.notNeeded ? "Обход не нужен" : Model.presetTitle(sp.recommendedName()) }
      Hint {
        Layout.fillWidth: true
        // Same two sentences as Обзор: the tabs must not answer the same
        // question differently.
        text: recCard.notNeeded ? Model.NOT_NEEDED_TEXT + ". " + Model.NOT_NEEDED_EXPL : sp.recommendedText()
      }
      RowLayout {
        Layout.fillWidth: true
        visible: !recCard.notNeeded
        PrimaryButton {
          enabled: root.ready && root.svc.installed && !root.svc.busy
          text: "Включить " + Model.presetTitle(sp.recommendedName())
          tooltipText: "Включить обход со стратегией " + Model.presetTitle(sp.recommendedName())
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
      Button { bordered: true; text: "Обновить стратегии из Flowseal"; tooltipText: "Загрузить пресеты Flowseal заново"; onClicked: root.svc.updatePresets() }
      Button { bordered: true; text: "Новая стратегия"; tooltipText: "Своя стратегия nfqws2: имя и текст пресета"; onClicked: sp.edit("") }
      Button {
        bordered: true
        visible: root.ready && root.svc.isOn
        text: "Выключить обход"
        tooltipText: "Выключить обход без смены стратегии"
        onClicked: root.svc.turnOff()
      }
    }
    RowLayout {
      Layout.fillWidth: true
      visible: !sp.editing && !sp.showing
      Disclosure {
        caption: "Все стратегии (" + sp.totalPresets() + ", проверено " + sp.testedCount() + ")"
        expanded: sp.showAll
        onToggled: sp.showAll = !sp.showAll
      }
    }
    // Collapsed must not mean empty: the page still says what it knows and
    // offers the one action that fills it.
    Card {
      id: collapsedCard
      visible: !sp.editing && !sp.showing && !sp.showAll
      readonly property string bestName: sp.recommendedName()
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)
        Label { Layout.fillWidth: true; text: "Лучшая: " + Model.presetTitle(collapsedCard.bestName) }
        Hint { Layout.fillWidth: true; text: sp.recommendedText() }
        Hint { Layout.fillWidth: true; text: "Список из " + sp.totalPresets() + " стратегий свёрнут: подбор по очереди проверяет их сам." }
      }
      RowLayout {
        Layout.fillWidth: true
        PrimaryButton {
          text: "Показать стратегии"
          tooltipText: "Развернуть список из " + sp.totalPresets() + " стратегий"
          onClicked: sp.showAll = true
        }
      }
    }
    TextField {
      id: filterField
      Layout.fillWidth: true
      visible: !sp.editing && !sp.showing && sp.showAll
      placeholderText: "Найти стратегию"
      text: sp.filter
      onTextChanged: sp.filter = text
    }
    RowLayout {
      Layout.fillWidth: true
      visible: !sp.editing && !sp.showing && sp.showAll
      spacing: Style.space(8)
      Toggle {
        Layout.fillWidth: true
        label: "Скрыть стратегии хуже базы"
        description: (sp.hiddenWorseCount > 0 ? "Сейчас скрыто " + sp.hiddenWorseCount + ". " : "") + "Плохие стратегии остаются в файле, но не показываются в списке."
        checked: sp.onlyGood
        foreground: root.fg
        onClicked: sp.onlyGood = !sp.onlyGood
      }
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
            PanelSectionHeader {
              Layout.fillWidth: true
              text: typeof Model.groupTitle === "function" ? Model.groupTitle(modelData.group) : modelData.group
              foreground: root.fg
              fontFamily: root.fontFamily
            }
            PanelSeparator { Layout.fillWidth: true; foreground: root.fg }
            Repeater {
              id: rowsRep
              model: sp.groupRows(modelData)
              delegate: Item {
                id: stratItem
                required property var modelData
                property bool isSpecial: modelData.expander !== undefined || modelData.collapse === true || modelData.tiesExpander !== undefined || modelData.tiesCollapse === true
                Layout.fillWidth: true
                implicitHeight: stratLoader.item ? stratLoader.item.implicitHeight : 0

                // Special rows (expanders, ties) are simple clickable Hint-style rows
                Loader {
                  id: stratLoader
                  anchors.fill: parent
                  sourceComponent: stratItem.isSpecial ? specialRowComp : normalRowComp
                }

                Component {
                  id: specialRowComp
                  Item {
                    // Anchored children give an Item no implicit height, which
                    // would collapse every expander row to nothing.
                    implicitHeight: stratRow.implicitHeight + Style.space(14)
                    TapHandler {
                      onTapped: {
                        if (stratItem.modelData.expander !== undefined || stratItem.modelData.collapse === true) sp.toggleMore(stratItem.modelData.group)
                        else if (stratItem.modelData.tiesExpander !== undefined || stratItem.modelData.tiesCollapse === true) sp.toggleTies(stratItem.modelData.group)
                      }
                    }
                    RowLayout {
                      id: stratRow
                      anchors.fill: parent
                      anchors.margins: Style.space(7)
                      Label {
                        Layout.fillWidth: true
                        color: root.dim
                        text: stratItem.modelData.collapse === true ? "▾ свернуть" : stratItem.modelData.tiesCollapse === true ? "▾ свернуть" : stratItem.modelData.tiesExpander !== undefined ? "▸ ещё " + stratItem.modelData.tiesExpander + " с тем же результатом" : "▸ ещё " + stratItem.modelData.expander + " не проверялись"
                      }
                    }
                  }
                }

                Component {
                  id: normalRowComp
                  CursorSurface {
                    property bool isActive: root.ready && root.svc.preset === stratItem.modelData.name
                    property bool isBest: {
                      var br = sp.pickRow(stratItem.modelData.name)
                      return !!(br && br.chosen)
                    }
                    property string flowSrc: sp.flowsealSource(stratItem.modelData.name)
                    property string scoreLine: {
                      var r = sp.pickRow(stratItem.modelData.name)
                      if (!r || (r.total | 0) <= 0) return "не проверялась"
                      var s = r.score + "/" + r.total
                      if (sp.isTied(stratItem.modelData.name)) s += " · = без обхода"
                      else if (sp.isWorse(stratItem.modelData.name)) s += " · ⚠ хуже, чем без обхода"
                      else if (r.chosen) s += " · лучшая"
                      return s
                    }
                    property string tipText: {
                      var t = Model.presetTitle(stratItem.modelData.name)
                      if (flowSrc !== "") t += "\n" + flowSrc
                      t += "\nEnter применит"
                      return t
                    }
                    property bool moreActionsOpen: sp.moreOpen[stratItem.modelData.name] === true
                    foreground: root.fg
                    Layout.fillWidth: true
                    current: isActive
                    hasCursor: sp.selectedName === stratItem.modelData.name
                    Accessible.role: Accessible.Button
                    Accessible.name: Model.presetTitle(stratItem.modelData.name) + (isActive ? ", активна" : "") + (sp.isTied(stratItem.modelData.name) ? ", как без обхода" : (isBest ? ", лучшая" : ""))
                    HoverHandler {
                      id: hover
                      onHoveredChanged: {
                        if (hovered) {
                          sp.selectedName = stratItem.modelData.name
                          if (sp.armDelete !== "" && sp.armDelete !== stratItem.modelData.name) sp.armDelete = ""
                        }
                      }
                    }
                    TapHandler {
                      onTapped: {
                        sp.selectedName = stratItem.modelData.name
                        if (sp.armDelete !== "" && sp.armDelete !== stratItem.modelData.name) sp.armDelete = ""
                      }
                    }
                    PanelToolTip {
                      visible: hover.hovered && tipText !== ""
                      text: tipText
                      fontFamily: root.fontFamily
                    }
                    // The surface is not layout-managed, so it may anchor one
                    // column; the rows inside that column must not anchor, or
                    // Qt warns and their height is never measured.
                    implicitHeight: rowCol.implicitHeight + Style.space(14)
                    ColumnLayout {
                      id: rowCol
                      anchors.fill: parent
                      anchors.margins: Style.space(7)
                      spacing: Style.space(6)
                      // Main row
                      RowLayout {
                        id: mainRow
                        Layout.fillWidth: true
                        spacing: Style.space(6)
                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: 0
                          RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(6)
                            Label { Layout.fillWidth: true; fixedWidth: true; text: Model.presetTitle(stratItem.modelData.name); font.bold: true }
                            BorderSurface {
                              visible: isActive || isBest
                              implicitWidth: activeText.implicitWidth + Style.space(10)
                              implicitHeight: activeText.implicitHeight + Style.space(4)
                              color: isActive ? Style.selectedFillFor(root.fg, Color.accent) : "transparent"
                              borderSpec: isActive ? Border.controlSpec("selected", root.fg, Color.accent) : Border.controlSpec("normal", root.fg, Color.accent)
                              radius: Style.cornerRadius
                              Text {
                                id: activeText
                                anchors.centerIn: parent
                                text: isActive && isBest ? "● активна · ★ лучшая" : (isActive ? "● активна" : "★ лучшая")
                                color: isActive ? Style.selectedStateColor(root.fg, Color.accent) : root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                              }
                            }
                          }
                          Hint {
                            Layout.fillWidth: true
                            color: sp.isWorse(stratItem.modelData.name) ? root.bad : root.dim
                            text: scoreLine
                          }
                          Hint {
                            Layout.fillWidth: true
                            visible: (sp.selectedName === stratItem.modelData.name || isActive) && !moreActionsOpen
                            color: sp.isWorse(stratItem.modelData.name) ? root.bad : root.dim
                            text: sp.rowSubtitle(stratItem.modelData)
                          }
                          Hint {
                            Layout.fillWidth: true
                            visible: (sp.selectedName === stratItem.modelData.name || isActive) && flowSrc !== "" && !moreActionsOpen
                            color: root.dim
                            text: flowSrc
                          }
                        }
                        // Apply button (only when not active)
                        Button {
                          bordered: true
                          visible: !isActive && sp.selectedName === stratItem.modelData.name
                          enabled: root.ready && !root.svc.busy
                          text: "Применить"
                          tooltipText: "Применить " + Model.presetTitle(stratItem.modelData.name)
                          onClicked: root.svc.setOption("preset", stratItem.modelData.name)
                        }
                        // Ellipsis button to toggle more actions
                        Button {
                          bordered: true
                          visible: sp.selectedName === stratItem.modelData.name
                          text: "⋯"
                          tooltipText: moreActionsOpen ? "Скрыть действия" : "Действия"
                          onClicked: {
                            var e = Object.assign({}, sp.moreOpen)
                            e[stratItem.modelData.name] = !moreActionsOpen
                            sp.moreOpen = e
                          }
                        }
                      }
                      // Inline action row (shown when moreActionsOpen is true)
                      RowLayout {
                        id: actionRow
                        Layout.fillWidth: true
                        visible: moreActionsOpen
                        spacing: Style.space(6)
                        Button {
                          bordered: true
                          text: "Показать"
                          tooltipText: "Показать текст пресета"
                          onClicked: sp.show(stratItem.modelData.name)
                        }
                        Button {
                          visible: stratItem.modelData.name.indexOf("my-") === 0
                          bordered: true
                          text: "Изменить"
                          tooltipText: "Изменить свою стратегию"
                          onClicked: sp.edit(stratItem.modelData.name)
                        }
                        Button {
                          visible: stratItem.modelData.name.indexOf("my-") === 0 && root.svc.preset !== stratItem.modelData.name
                          bordered: true
                          foreground: root.bad
                          text: sp.armDelete === stratItem.modelData.name ? "Точно удалить?" : "Удалить"
                          tooltipText: sp.armDelete === stratItem.modelData.name ? "Нажмите ещё раз для удаления" : "Удалить свою стратегию"
                          onClicked: {
                            if (sp.armDelete === stratItem.modelData.name) { sp.armDelete = ""; disarmTimer.stop(); root.svc.removeCustom(stratItem.modelData.name) }
                            else { sp.armDelete = stratItem.modelData.name; disarmTimer.restart() }
                          }
                        }
                        Button {
                          visible: sp.armDelete === stratItem.modelData.name && stratItem.modelData.name.indexOf("my-") === 0
                          bordered: true
                          text: "Отмена"
                          tooltipText: "Оставить стратегию"
                          onClicked: { sp.armDelete = ""; disarmTimer.stop() }
                        }
                      }
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
        PanelSectionHeader { Layout.fillWidth: true; text: Model.presetTitle(sp.shownName); foreground: root.fg; fontFamily: root.fontFamily }
        Button { bordered: true; text: "Закрыть"; tooltipText: "Закрыть просмотр (Esc)"; onClicked: sp.showing = false }
      }
      Hint {
        Layout.fillWidth: true
        visible: sp.showError !== ""
        text: sp.showError
      }
      Hint {
        Layout.fillWidth: true
        visible: sp.shownText !== "" && !sp.isSectionFormat(sp.shownText)
        text: "Полный пресет Flowseal: правится через копию как свою."
      }
      Editor {
        id: viewerEditor
        readOnly: true
        text: sp.shownText
      }
      RowLayout {
        Button {
          bordered: true
          visible: root.ready && root.svc.preset !== sp.shownName
          text: "Применить"
          tooltipText: "Применить " + Model.presetTitle(sp.shownName)
          onClicked: root.svc.setOption("preset", sp.shownName)
        }
        Button {
          bordered: true
          visible: sp.shownText !== ""
          text: "Скопировать как свою"
          tooltipText: "Открыть копию в редакторе своих стратегий"
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
        Button {
          bordered: true
          text: "Сохранить"
          enabled: sp.editName.trim() !== ""
          tooltipText: "Сохранить свою стратегию"
          onClicked: root.svc.saveCustom(sp.editName.trim(), editor.text, function(r) { if (r.ok) sp.editing = false })
        }
        Button { bordered: true; text: "Отмена"; onClicked: sp.editing = false }
      }
    }
  }

  component ListsPage: ColumnLayout {
    id: lp
    spacing: Style.space(10)
    property string current: "list-general-user"
    readonly property bool editable: current.indexOf("-user") !== -1
    readonly property bool uiBlocked: listDrop.popupOpen || listEditor.area.activeFocus
    readonly property string kind: current.indexOf("ipset") === 0 ? "ipset" : "host"
    property string info: ""
    property string loadedText: ""
    property string saveResult: ""
    property bool restartAfterSave: true
    function exampleText() {
      if (lp.kind === "ipset") return "# пример:\n# 1.2.3.0/24\n# 2001:db8::/32\n"
      return "# пример:\nexample.com\n# sub.example.org\n"
    }
    readonly property var myNames: [
      { value: "list-general-user", label: "Мои: сайты (через обход)" },
      { value: "list-exclude-user", label: "Мои: исключения (без обхода)" },
      { value: "ipset-all-user", label: "Мои: IP-сети (через обход)" },
      { value: "ipset-exclude-user", label: "Мои: IP-исключения" }
    ]
    readonly property var builtinNames: [
      { value: "list-general", label: "Встроенные: общий список" },
      { value: "list-google", label: "Встроенные: YouTube/Google" },
      { value: "list-exclude", label: "Встроенные: исключения" },
      { value: "ipset-all", label: "Встроенные: IP-сети" },
      { value: "ipset-exclude", label: "Встроенные: IP-исключения" }
    ]
    readonly property var names: myNames.concat(builtinNames)

    function load() {
      if (!root.ready) return
      listEditor.text = ""
      loadedText = ""
      saveResult = ""
      info = "Загрузка…"
      root.svc.loadText(["list", "show", current], function(r) {
        if (!r.ok) { info = r.message; return }
        listEditor.text = r.data.text + (r.data.text ? "\n" : "")
        loadedText = listEditor.text
        info = "Загружено: " + r.data.count + " строк" + (r.data.truncated ? " (показаны первые 5000)" : "")
      })
    }
    function savedMessage(count, dropped) {
      return "Сохранено: " + count + " строк, отброшено " + dropped
    }
    function save() {
      root.svc.saveList(lp.current, listEditor.text, function(r) {
        if (r.ok) {
          var msg = lp.savedMessage(r.data.count, r.data.dropped || 0)
          root.svc.flash(msg)
          lp.loadedText = listEditor.text
          lp.info = msg
          lp.saveResult = msg + (r.data.restarted ? " · обход перезапущен" : " · без перезапуска")
        }
      }, lp.restartAfterSave)
    }
    onCurrentChanged: { lp.saveResult = ""; load() }
    Component.onCompleted: load()

    RowLayout {
      Layout.fillWidth: true
      Dropdown {
        id: listDrop
        Layout.preferredWidth: Style.space(320)
        label: "Список"
        value: lp.current
        options: lp.names
        onChanged: function(v) { lp.current = v }
      }
      Hint {
        visible: lp.editable && listEditor.text !== lp.loadedText
        color: root.bad
        text: "не сохранено"
      }
      Hint { Layout.fillWidth: true; text: lp.info }
      Button { bordered: true; text: "Обновить списки из Flowseal"; tooltipText: "Загрузить списки Flowseal заново"; onClicked: root.svc.updateLists() }
    }
    Hint {
      Layout.fillWidth: true
      text: lp.editable ? "Мои — можно править. По одному домену (поддомены включаются сами) или IP/CIDR на строку. Неверные строки отбрасываются."
                        : "Встроенные (только чтение). Свои записи добавляйте в «Мои …»."
    }
    // The empty state is a real state, not a three-line placeholder that reads
    // like content.
    Card {
      visible: lp.editable && listEditor.text === ""
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)
        Label { Layout.fillWidth: true; text: "Список пуст — так и должно быть" }
        Hint { Layout.fillWidth: true; text: "Встроенные списки Flowseal уже покрывают YouTube и Discord. Добавьте свой домен, только если он не открывается." }
      }
      RowLayout {
        Layout.fillWidth: true
        PrimaryButton {
          text: "Вставить пример"
          tooltipText: "Вставить пример записей в редактор"
          onClicked: listEditor.text += lp.exampleText()
        }
      }
    }
    Editor {
      id: listEditor
      readOnly: !lp.editable
      placeholderText: lp.editable ? "Пусто" : "Список только для чтения"
    }
    RowLayout {
      id: listActions
      visible: lp.editable
      spacing: Style.space(8)
      property var liveCounts: (typeof Model.validLines === "function") ? Model.validLines(listEditor.text, lp.kind) : { valid: Model.countLines(listEditor.text), dropped: 0 }
      property bool changed: listEditor.text !== lp.loadedText
      readonly property bool canSave: root.ready && !root.svc.busy && (listActions.liveCounts.valid > 0 || (listActions.liveCounts.valid === 0 && listActions.changed))
      // Saving is the page's filled action; clearing is destructive and never
      // takes the emphasis.
      PrimaryButton {
        visible: listActions.liveCounts.valid > 0
        enabled: listActions.canSave
        text: "Сохранить список"
        tooltipText: "Сохранить список (" + listActions.liveCounts.valid + " строк, отброшено " + listActions.liveCounts.dropped + ")" + (lp.restartAfterSave ? " и перезапустить обход" : " без перезапуска обхода")
        onClicked: lp.save()
      }
      Button {
        bordered: true
        foreground: root.bad
        visible: listActions.liveCounts.valid === 0
        enabled: listActions.canSave
        text: "Очистить и сохранить"
        tooltipText: "Удалить все записи и сохранить пустой список" + (lp.restartAfterSave ? " с перезапуском обхода" : " без перезапуска обхода")
        onClicked: lp.save()
      }
      Hint {
        text: {
          var c = listActions.liveCounts
          var s = c.valid + " строк"
          if (c.dropped > 0) s += " · отброшено " + c.dropped
          return s
        }
      }
    }
    Toggle {
      Layout.fillWidth: true
      visible: lp.editable
      label: "Перезапустить обход после сохранения"
      description: "Обход перезапускается, чтобы новые списки применились. Займёт несколько секунд."
      checked: lp.restartAfterSave
      foreground: root.fg
      onClicked: lp.restartAfterSave = !lp.restartAfterSave
    }
    Hint {
      Layout.fillWidth: true
      visible: lp.editable && lp.saveResult !== ""
      text: lp.saveResult
    }
  }

  component SearchPage: ScrollView {
    id: se
    property bool showFull: false
    property bool onlyImportantBc: true
    property bool tiesOpen: false
    property bool bcFollow: true
    // The current blockcheck2 phase, raw and localised. The raw form is also
    // used to drop the line from the journal below, so the same sentence never
    // appears twice on screen.
    readonly property string phaseRaw: {
      if (!root.ready || !root.svc.blockcheck) return ""
      var tail = root.svc.blockcheck.tail || []
      for (var i = tail.length - 1; i >= 0; i--) {
        var s = String(tail[i])
        if (s.substring(0, 2) === "- " || s.charAt(0) === "*") return s
      }
      return ""
    }
    readonly property string phaseText: {
      if (se.phaseRaw === "") return ""
      var bare = se.phaseRaw.replace(/^\* ?/, "").replace(/^- /, "")
      return (typeof Model.blockcheckPhase === "function") ? Model.blockcheckPhase(bare) : bare
    }
    function logLine(line) {
      return se.phaseRaw !== "" && String(line) === se.phaseRaw ? se.phaseText : String(line)
    }
    function focusDomains() { domains.forceActiveFocus() }
    readonly property bool uiBlocked: domains.activeFocus || level.popupOpen || bcEditor.area.activeFocus
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
          PanelSectionHeader { Layout.fillWidth: true; text: "Быстрый подбор"; foreground: root.fg; fontFamily: root.fontFamily }
          // Fast path is the page's filled action; the deep search below is
          // the power-user fallback and stays secondary.
          PrimaryButton {
            visible: !(root.ready && root.svc.busyLabel === "автоподбор")
            enabled: root.ready && !root.svc.busy
            text: "Запустить"
            tooltipText: "Запустить быстрый подбор (1–3 минуты)"
            onClicked: root.svc.autopick([])
          }
          Button {
            bordered: true
            visible: root.ready && root.svc.busyLabel === "автоподбор"
            text: "Остановить"
            tooltipText: "Остановить подбор"
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
          font.bold: true
          text: "✓ Без обхода открывается не хуже: обход сейчас не нужен, или он уже работает на роутере или в VPN"
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
          }
          PanelSeparator {
            Layout.fillWidth: true
            foreground: root.fg
            visible: se.pickGroup.best !== null
          }
          PickRow {
            visible: se.pickGroup.best !== null
            row: se.pickGroup.best || {}
            baseScore: se.pickBase
          }
          RowLayout {
            Layout.fillWidth: true
            visible: se.pickGroup.ties.length > 0
            Disclosure {
              caption: "ещё " + se.pickGroup.ties.length + " с тем же результатом"
              expanded: se.tiesOpen
              onToggled: se.tiesOpen = !se.tiesOpen
            }
          }
          Repeater {
            model: se.tiesOpen ? se.pickGroup.ties : []
            delegate: PickRow {
              required property var modelData
              row: modelData
              baseScore: se.pickBase
            }
          }
          Repeater {
            model: se.pickGroup.rest
            delegate: PickRow {
              required property var modelData
              row: modelData
              baseScore: se.pickBase
            }
          }
          Hint {
            Layout.fillWidth: true
            visible: root.ready && root.svc.autopickResult.time !== undefined && (root.svc.autopickResult.rows || []).length > 0
            text: "● — выбрана сейчас · полоса и число рядом с ним: минус — хуже, чем без обхода, плюс — лучше; «база» — результат без обхода"
          }
        }
      }

      Card {
        id: blockcheckCard
        function bindMissing() {
          if (!root.ready) return false
          var items = root.svc.doctorItems || []
          for (var i = 0; i < items.length; i++)
            if (items[i].name === "host/nslookup" && !items[i].ok) return true
          return false
        }
        function vpnOn() {
          if (!root.ready) return false
          var items = root.svc.doctorItems || []
          for (var i = 0; i < items.length; i++)
            if (items[i].name === "No VPN tunnel" && !items[i].ok) return true
          return false
        }
        RowLayout {
          Layout.fillWidth: true
          PanelSectionHeader { Layout.fillWidth: true; text: "Глубокий поиск: blockcheck2"; foreground: root.fg; fontFamily: root.fontFamily }
          Button {
            bordered: true
            // Always visible, so the reason is on screen instead of the button
            // quietly disappearing; it never copies anything behind your back.
            enabled: root.ready && (root.svc.blockcheckRunning || (!blockcheckCard.vpnOn() && !blockcheckCard.bindMissing()))
            text: root.ready && root.svc.blockcheckRunning ? "Остановить" : "Запустить"
            tooltipText: root.svc.blockcheckRunning ? "Остановить глубокий поиск"
                : blockcheckCard.vpnOn() ? "Выключите VPN-туннель (omarchy-xray TUN) — поиск через туннель бессмыслен"
                : blockcheckCard.bindMissing() ? "Нужен пакет bind: omarchy pkg add bind"
                : "Запустить глубокий поиск"
            onClicked: {
              if (root.svc.blockcheckRunning) { root.svc.blockcheckStop(); return }
              se.bcFollow = true
              root.svc.blockcheckStart(domains.text.split(/[\s,]+/).filter(function(d) { return d !== "" }), level.value)
            }
          }
        }
        Label {
          Layout.fillWidth: true
          visible: blockcheckCard.vpnOn() && !root.svc.blockcheckRunning
          color: root.bad
          font.bold: true
          text: "Выключите VPN-туннель (omarchy-xray TUN): поиск через туннель бессмыслен"
        }
        // The remedy is one copyable field with one copy action, not three
        // unrelated fragments sharing a row with the run button.
        RowLayout {
          Layout.fillWidth: true
          visible: !root.svc.blockcheckRunning && blockcheckCard.bindMissing() && !blockcheckCard.vpnOn()
          spacing: Style.space(8)
          Label {
            Layout.fillWidth: true
            fixedWidth: true
            color: root.bad
            font.bold: true
            text: "Нужен bind для blockcheck2"
          }
          BorderSurface {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: bindCmd.implicitWidth + Style.space(16)
            implicitHeight: bindCmd.implicitHeight + Style.space(8)
            color: Style.normalFillFor(root.fg, Color.accent)
            borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
            radius: Style.cornerRadius
            Text {
              id: bindCmd
              anchors.centerIn: parent
              text: "omarchy pkg add bind"
              color: root.fg
              font.family: root.monoFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
          }
          Button {
            bordered: true
            text: "Скопировать команду"
            tooltipText: "Скопировать команду установки bind (установка — вручную)"
            onClicked: root.copyText("omarchy pkg add bind")
          }
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
            Layout.preferredWidth: Style.space(180)
            label: "Режим"
            value: "quick"
            options: [{ value: "quick", label: "быстрый" }, { value: "standard", label: "обычный" }, { value: "force", label: "полный" }]
            onChanged: function(v) { value = v }
          }
        }
        Hint {
          Layout.fillWidth: true
          text: {
            var c = Model.validHosts(domains.text)
            var base = "Подставлено из неуспешных проверок — можно править"
            if ((c.total | 0) === 0) return base
            return base + " · " + c.valid + " из " + c.total + " корректны"
          }
        }
        Repeater {
          model: root.ready && root.svc.blockcheck ? root.svc.blockcheck.found : []
          delegate: CursorSurface {
            required property var modelData
            required property int index
            foreground: root.fg
            Layout.fillWidth: true
            implicitHeight: foundInner.implicitHeight + Style.space(10)
            hasCursor: foundHover.hovered
            HoverHandler { id: foundHover }
            RowLayout {
              id: foundInner
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)
              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { Layout.fillWidth: true; text: Model.findingTitle(modelData); font.bold: true }
                Hint { Layout.fillWidth: true; text: modelData.args; font.family: root.monoFamily }
              }
              Button {
                bordered: true
                text: "Сохранить"
                tooltipText: "Сохранить найденное как свою стратегию"
                onClicked: root.svc.blockcheckSave(index)
              }
            }
          }
        }
        Hint {
          visible: root.ready && root.svc.blockcheck !== null && root.svc.blockcheck.lines > 0
          text: {
            if (!root.ready || !root.svc.blockcheck) return ""
            var bc = root.svc.blockcheck
            var prefix = bc.done ? "Готово. " : root.svc.blockcheckRunning ? "Идёт поиск… " : ""
            if (se.phaseRaw !== "") return prefix + se.phaseText
            return prefix + bc.lines + " строк журнала"
          }
        }
        Toggle {
          Layout.fillWidth: true
          visible: root.ready && root.svc.blockcheck !== null && root.svc.blockcheck.lines > 0
          label: "Показать весь журнал"
          description: "Выключите, чтобы оставить только ошибки и найденные стратегии."
          checked: se.showFull
          foreground: root.fg
          onClicked: se.showFull = !se.showFull
        }
        Toggle {
          Layout.fillWidth: true
          visible: root.ready && root.svc.blockcheck !== null && root.svc.blockcheck.lines > 0 && !se.showFull
          label: "Только важное"
          description: "Ошибки, найденные стратегии и итог перебора; служебные строки zapret2 скрыты."
          checked: se.onlyImportantBc
          foreground: root.fg
          onClicked: se.onlyImportantBc = !se.onlyImportantBc
        }
        Editor {
          id: bcEditor
          // Sized to the content, so four lines do not sit in an empty box.
          Layout.preferredHeight: Math.min(Style.space(240), Math.max(Style.space(60), bcEditor.area.contentHeight + Style.space(16)))
          Layout.fillHeight: false
          readOnly: true
          visible: root.ready && root.svc.blockcheck !== null && root.svc.blockcheck.lines > 0
          area.wrapMode: TextEdit.NoWrap
          text: {
            if (!root.ready || !root.svc.blockcheck) return ""
            // The headline above already shows the phase line, so it is dropped
            // here; every line is localised before it reaches the user.
            var tail = root.svc.blockcheck.tail.filter(function(l) { return String(l) !== se.phaseRaw })
            if (se.showFull) return tail.map(function(l) { return se.logLine(l) }).join("\n")
            var lines = tail.filter(function(l) {
              var s = String(l)
              return s.substring(0, 5) === "!!!!!" || s.charAt(0) === "*" || s.indexOf("AVAILABLE") !== -1 || s.toLowerCase().indexOf("working strategy") !== -1
            })
            if (se.onlyImportantBc && typeof Model.importantLog === "function") lines = lines.filter(function(l) { return Model.importantLog(l) })
            return lines.map(function(l) { return se.logLine(l) }).join("\n")
          }
          area.onTextChanged: if (se.bcFollow) area.cursorPosition = area.length
          Connections {
            target: bcEditor.contentItem
            function onContentYChanged() {
              var f = bcEditor.contentItem
              if (f.moving || f.dragging || f.flicking) se.bcFollow = f.atYEnd
            }
            function onMovementEnded() { se.bcFollow = bcEditor.contentItem.atYEnd }
          }
        }
      }
    }
  }

  component EnginePage: ScrollView {
    id: ep
    clip: true
    contentWidth: availableWidth
    property bool armRemove: false
    property int hoverDoc: -1
    property bool onlyImportant: true
    readonly property bool uiBlocked: logEditor.area.activeFocus
    Timer { id: armRemoveTimer; interval: 4000; onTriggered: ep.armRemove = false }
    ColumnLayout {
      width: parent.width
      spacing: Style.space(12)
      // So the last card can be scrolled fully into view instead of being cut
      // at the viewport edge.
      Layout.bottomMargin: Style.space(24)

      Card {
        id: engineCard
        PanelSectionHeader {
          Layout.fillWidth: true
          text: "Движок: " + (root.ready && root.svc.st && root.svc.st.engine ? root.svc.st.engine : "не установлен")
          foreground: root.fg
          fontFamily: root.fontFamily
        }
        Hint { Layout.fillWidth: true; text: "bol-van/zapret2: nfqws2 + Lua. Обновление скачивает последний релиз, сверяет sha256 и спрашивает пароль. Предыдущая версия остаётся рядом." }
        RowLayout {
          // The engine update is this page's one filled action. The plugin
          // update lives in the diagnostics row below, where it is named.
          PrimaryButton {
            text: "Обновить движок (zapret2)"
            tooltipText: "Обновить движок zapret2 до последнего релиза (спросит пароль)"
            enabled: root.ready && root.svc.installed && !root.svc.busy
            onClicked: root.svc.engineUpdate()
          }
        }
      }

      Card {
        RowLayout {
          Layout.fillWidth: true
          PanelSectionHeader { Layout.fillWidth: true; text: "Диагностика"; foreground: root.fg; fontFamily: root.fontFamily }
          Button { bordered: true; text: "Повторить"; tooltipText: "Повторить диагностику"; onClicked: root.svc.runDoctor() }
        }
        Repeater {
          model: root.ready ? root.svc.doctorItems : []
          delegate: CursorSurface {
            id: docRow
            required property var modelData
            required property int index
            property string severity: (typeof Model.doctorSeverity === "function") ? Model.doctorSeverity(modelData.name, modelData.ok, modelData.detail) : (modelData.ok ? "ok" : "error")
            property string glyph: severity === "ok" ? "✓ " : severity === "action" ? "! " : severity === "optional" ? "· " : "✗ "
            foreground: root.fg
            Layout.fillWidth: true
            implicitHeight: docInner.implicitHeight + Style.space(10)
            hasCursor: ep.hoverDoc === index
            Accessible.role: Accessible.StaticText
            Accessible.name: (severity === "ok" ? "в порядке: " : severity === "action" ? "нужно действие: " : severity === "optional" ? "необязательно: " : "ошибка: ") + (typeof Model.doctorName === "function" ? Model.doctorName(modelData.name) : modelData.name)
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
              onContainsMouseChanged: if (containsMouse) ep.hoverDoc = index
            }
            // Two real columns: the detail text starts at one left edge for
            // every row, so the list reads as a table instead of ragged prose.
            GridLayout {
              id: docInner
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              columns: 3
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(2)
              Label {
                Layout.preferredWidth: Style.space(230)
                Layout.minimumWidth: Style.space(230)
                fixedWidth: true
                text: docRow.glyph + (typeof Model.doctorName === "function" ? Model.doctorName(modelData.name) : modelData.name)
                // "Нужно действие" is accent, not failure: only a real error
                // gets the error colour.
                color: docRow.severity === "ok" ? root.fg : docRow.severity === "optional" ? root.dim : docRow.severity === "action" ? Color.accent : root.bad
              }
              Hint {
                Layout.fillWidth: true
                fixedWidth: true
                visible: text !== ""
                text: {
                  var d = Model.doctorDetail(modelData.name, modelData.detail)
                  var dn = typeof Model.doctorName === "function" ? Model.doctorName(modelData.name) : modelData.name
                  if ((modelData.name === "Setup" || dn === "Установка") && root.ready && root.svc.st && root.svc.st.engine && d.indexOf(String(root.svc.st.engine)) !== -1) return ""
                  return d
                }
              }
              // Labelled actions: a 20px glyph was not a target, and the fix
              // for the plugin row is the button, not a copy.
              Button {
                bordered: true
                visible: !modelData.ok && (String(modelData.name).indexOf("host") !== -1 || String(modelData.name).indexOf("nslookup") !== -1 || String(modelData.detail).indexOf("bind") !== -1)
                text: "Скопировать"
                tooltipText: "Скопировать команду: omarchy pkg add bind"
                foreground: root.fg
                onClicked: root.copyText("omarchy pkg add bind")
              }
              Button {
                bordered: true
                visible: !modelData.ok && String(modelData.name).indexOf("Plugin and system copy") !== -1
                text: "Обновить плагин"
                tooltipText: "Установить обновление системной части плагина (спросит пароль)"
                foreground: root.fg
                onClicked: root.svc.updateApp()
              }
              Item { Layout.preferredWidth: 1 }
            }
          }
        }
      }

      Card {
        RowLayout {
          Layout.fillWidth: true
          PanelSectionHeader { Layout.fillWidth: true; text: "Журнал службы"; foreground: root.fg; fontFamily: root.fontFamily }
          Button { bordered: true; text: "Обновить"; tooltipText: "Обновить журнал"; onClicked: root.svc.loadLogs() }
        }
        Hint { visible: root.ready && root.svc.logNote !== ""; Layout.fillWidth: true; text: root.ready ? root.svc.logNote : "" }
        Toggle {
          Layout.fillWidth: true
          label: "Только важное"
          description: "Ошибки, предупреждения и перезапуски; информационные строки скрыты."
          checked: ep.onlyImportant
          foreground: root.fg
          onClicked: ep.onlyImportant = !ep.onlyImportant
        }
        Editor {
          id: logEditor
          Layout.preferredHeight: Math.min(Style.space(240), Math.max(Style.space(60), logEditor.area.contentHeight + Style.space(16)))
          Layout.fillHeight: false
          readOnly: true
          area.wrapMode: TextEdit.NoWrap
          text: {
            if (!root.ready) return ""
            var lines = root.svc.logLines.slice()
            if (ep.onlyImportant && typeof Model.importantLog === "function") {
              var kept = lines.filter(function(l) { return Model.importantLog(Model.shortLog(l)) })
              if (kept.length > 0) lines = kept
            }
            return lines.map(function(l) { return Model.shortLog(l) }).join("\n")
          }
        }
      }

      Card {
        visible: root.ready && root.svc.installed
        PanelSectionHeader { Layout.fillWidth: true; text: "Удаление"; foreground: root.fg; fontFamily: root.fontFamily }
        Hint { Layout.fillWidth: true; text: "Останавливает обход и удаляет всё, что поставила установка: /opt/omarchy-zapret2, юниты, правило polkit. Ваши списки и стратегии в /var/lib/omarchy-zapret2 остаются, если не выбрать «вместе с данными»." }
        RowLayout {
          Button { bordered: true; foreground: root.bad; text: ep.armRemove ? "Точно удалить?" : "Удалить"; tooltipText: ep.armRemove ? "Нажмите ещё раз для удаления" : "Удалить движок и настройки плагина"; onClicked: { if (ep.armRemove) { ep.armRemove = false; armRemoveTimer.stop(); root.svc.removeAll(false) } else { ep.armRemove = true; armRemoveTimer.restart() } } }
          Button { visible: ep.armRemove; bordered: true; foreground: root.bad; text: "Вместе с данными"; tooltipText: "Удалить и свои списки и стратегии"; onClicked: { ep.armRemove = false; armRemoveTimer.stop(); root.svc.removeAll(true) } }
          Button { visible: ep.armRemove; bordered: true; text: "Отмена"; tooltipText: "Оставить всё как есть"; onClicked: { ep.armRemove = false; armRemoveTimer.stop() } }
        }
      }
    }
  }

  component SettingsPage: ScrollView {
    id: stp
    property bool showExtra: false
    property bool hostsConfirm: false
    readonly property bool uiBlocked: gameTcpField.activeFocus || gameUdpField.activeFocus
        || gameDrop.popupOpen || ipsetDrop.popupOpen || voiceDrop.popupOpen
        || discordFakeDrop.popupOpen || gameFakeDrop.popupOpen
    Timer { id: hostsTimer; interval: 4000; onTriggered: stp.hostsConfirm = false }
    clip: true
    contentWidth: availableWidth
    ColumnLayout {
      width: parent.width
      spacing: Style.space(12)
      enabled: root.ready && root.svc.installed

      Card {
        Toggle {
          Layout.fillWidth: true
          label: "Включать при входе"
          description: "Шелл включает обход после входа в систему"
          checked: root.ready && root.svc.settings.autostart === true
          foreground: root.fg
          onClicked: root.svc.toggleAutostart()
        }
        Toggle {
          Layout.fillWidth: true
          label: "IPv6 (по умолчанию вкл)"
          description: "Обрабатывать и IPv6-соединения · не трогайте, если не уверены"
          checked: root.ready && root.svc.settings.ipv6 !== false
          foreground: root.fg
          onClicked: root.svc.toggleIpv6()
        }
      }

      Card {
        Dropdown {
          id: gameDrop
          Layout.fillWidth: true
          label: "Игровой фильтр"
          value: root.ready ? (root.svc.settings.game || "off") : "off"
          options: [{ value: "off", label: "Выключен" }, { value: "tcp", label: "TCP 1024–65535" },
                    { value: "udp", label: "UDP 1024–65535" }, { value: "all", label: "TCP и UDP" }]
          onChanged: function(v) { root.svc.setOption("game", v) }
        }
        Hint { Layout.fillWidth: true; text: "Обход для игр по IP-сетям (ipset). Нагружает сильнее: включайте, если игра не подключается." }
        RowLayout {
          Layout.fillWidth: true
          visible: root.ready && (root.svc.settings.game || "off") !== "off"
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Label { text: "Порты TCP" }
            TextField {
              id: gameTcpField
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
              id: gameUdpField
              Layout.fillWidth: true
              text: root.ready ? (root.svc.settings.gameUdp || "") : ""
              placeholderText: "например 1024-65535"
              onEditingFinished: root.svc.setOption("gameudp", text)
            }
          }
        }
        Dropdown {
          id: ipsetDrop
          Layout.fillWidth: true
          label: "IP-сети (ipset)"
          value: root.ready ? (root.svc.settings.ipset || "loaded") : "loaded"
          options: [{ value: "loaded", label: "По списку" }, { value: "none", label: "Не использовать" }, { value: "any", label: "Любой IP" }]
          onChanged: function(v) { root.svc.setOption("ipset", v) }
        }
        Dropdown {
          id: voiceDrop
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
          Disclosure {
            caption: "Дополнительно"
            expanded: stp.showExtra
            onToggled: stp.showExtra = !stp.showExtra
          }
        }
        Dropdown {
          id: discordFakeDrop
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
          id: gameFakeDrop
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
            PanelSectionHeader { Layout.fillWidth: true; text: "Hosts Flowseal"; foreground: root.fg; fontFamily: root.fontFamily }
            Hint { Layout.fillWidth: true; text: "Добавляет в /etc/hosts адреса Discord-серверов из репозитория Flowseal, нужен пароль" }
            Hint {
              Layout.fillWidth: true
              visible: root.ready && root.svc.hostsOn === true
              text: "Включён"
            }
          }
          Button {
            visible: root.ready && root.svc.hostsOn === true
            bordered: true
            enabled: root.ready && !root.svc.busy
            text: "Выключить"
            tooltipText: "Убрать записи из /etc/hosts (спросит пароль)"
            onClicked: root.svc.hostsSet(false)
          }
          // Enabling is the page's one filled action; turning it back off is a
          // revert and stays secondary.
          PrimaryButton {
            visible: !(root.ready && root.svc.hostsOn === true) && !stp.hostsConfirm
            text: "Включить"
            tooltipText: "Добавить адреса Discord-серверов из Flowseal в /etc/hosts (спросит пароль)"
            onClicked: { stp.hostsConfirm = true; hostsTimer.restart() }
          }
        }
        RowLayout {
          Layout.fillWidth: true
          visible: stp.hostsConfirm && !(root.ready && root.svc.hostsOn)
          Hint { Layout.fillWidth: true; text: "Изменит /etc/hosts, нужен пароль" }
          Button { bordered: true; text: "Подтвердить"; tooltipText: "Изменить /etc/hosts (спросит пароль)"; onClicked: { stp.hostsConfirm = false; hostsTimer.stop(); root.svc.hostsSet(true) } }
          Button { text: "Отмена"; tooltipText: "Оставить /etc/hosts как есть"; onClicked: { stp.hostsConfirm = false; hostsTimer.stop() } }
        }
      }

      Card {
        RowLayout {
          Layout.fillWidth: true
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            PanelSectionHeader { Layout.fillWidth: true; text: "Discord"; foreground: root.fg; fontFamily: root.fontFamily }
            Hint { Layout.fillWidth: true; text: "Помогает, если Discord не грузится после включения обхода; закройте Discord перед очисткой" }
          }
          Button { bordered: true; text: "Очистить кэш Discord"; tooltipText: "Удалить кэш Discord"; onClicked: root.svc.clearDiscordCache() }
        }
      }

      Card {
        PanelSectionHeader { Layout.fillWidth: true; text: "Горячие клавиши"; foreground: root.fg; fontFamily: root.fontFamily }
        Hint {
          Layout.fillWidth: true
          text: "Добавьте в ~/.config/hypr/bindings.lua (подставьте свои клавиши):"
        }
        Editor {
          id: hotkeysSnippet
          readOnly: true
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(90)
          placeholderText: ""
          text: 'o.bind("KEY", "Zapret2: Открыть", "omarchy-shell shell toggle krieziey.omarchy-zapret2 \'{}\'")\no.bind("KEY", "Zapret2: Обход", "omarchy-shell krieziey.omarchy-zapret2 toggleBypass")'
        }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          // A labelled action next to its snippet, not a lone glyph under it.
          Button {
            bordered: true
            text: "Скопировать сниппет"
            tooltipText: "Скопировать Lua-сниппет в буфер"
            foreground: root.fg
            onClicked: root.copyText(hotkeysSnippet.text)
          }
          Hint {
            Layout.fillWidth: true
            text: "Идентификатор krieziey.omarchy-zapret2 — ваш; вставьте строки в конец bindings.lua."
          }
        }
        Hint {
          Layout.fillWidth: true
          text: "Замените KEY на желаемые сочетания (например SUPER+Z, SUPER+SHIFT+Z). Первая команда — окно приложения, вторая — включить/выключить обход."
        }
      }
    }
  }
}
