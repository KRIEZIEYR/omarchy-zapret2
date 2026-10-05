import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
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
    if (tab === 3) svc.refreshBlockcheck()
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

  component Editor: ScrollView {
    property alias text: area.text
    property alias readOnly: area.readOnly
    property alias area: area
    Layout.fillWidth: true
    Layout.fillHeight: true
    clip: true
    background: Rectangle { color: Qt.rgba(0, 0, 0, 0.18); border.color: root.line; border.width: 1; radius: Style.cornerRadius }
    TextArea {
      id: area
      color: root.fg
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
                color: root.ready && root.svc.bypassState === "error" ? Color.urgent : root.fg
                filled: root.ready && root.svc.isOn
                warning: root.ready && root.svc.errorText !== ""
              }
              ColumnLayout {
                spacing: 0
                Text { text: "Zapret2"; color: root.ready && root.svc.isOn ? Color.accent : root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                Hint { text: root.ready ? Model.stateText(root.svc.st) : "Загрузка…"; color: root.ready && root.svc.isOn ? Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.75) }
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
              text: root.ready && root.svc.busy ? "Выполняется: " + root.svc.busyLabel + "…" : "Ctrl+1…6: вкладки · Ctrl+T: вкл/выкл"
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
              color: root.ready && root.svc.errorText !== "" ? Color.urgent : Color.accent
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
        RowLayout {
          Layout.fillWidth: true
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Text {
              Layout.fillWidth: true
              text: root.ready ? Model.stateText(root.svc.st) : ""
              color: root.ready && root.svc.bypassState === "error" ? Color.urgent : root.fg
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
          Label { text: root.ready && root.svc.isOn ? "Включён" : "Выключен" }
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
            return v.text
          }
          color: {
            if (!root.ready) return Color.popups.text
            var v = Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult)
            return v.tone === "good" ? Color.accent : (v.tone === "bad" || v.tone === "warn") ? Color.urgent : Color.popups.text
          }
        }
        RowLayout {
          Layout.fillWidth: true
          Button {
            bordered: true
            enabled: root.ready && root.svc.installed
            text: {
              if (!root.ready) return "Включить обход"
              var v = Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult)
              if (v.action === "autopick") return "Подобрать стратегию"
              return root.svc.isOn ? "Выключить обход" : "Включить обход"
            }
            onClicked: {
              var v = Model.verdict(root.svc.st, root.svc.check, root.svc.autopickResult)
              if (v.action === "autopick") { root.tab = 3; root.svc.autopick([]) }
              else root.svc.toggle()
            }
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
        RowLayout {
          Layout.fillWidth: true
          Label { Layout.fillWidth: true; font.bold: true; text: "Доступность" }
          Hint { text: root.ready ? Model.ago(root.svc.check.time) : "" }
          Button { bordered: true; text: "Проверить"; onClicked: root.svc.runCheck() }
        }
        Hint {
          Layout.fillWidth: true
          visible: root.ready && root.svc.check.preset !== undefined
          text: root.ready ? "Последняя проверка: стратегия " + Model.presetTitle(root.svc.check.preset)
                             + (root.svc.check.active ? ", обход был включён" : ", обход был выключен") : ""
        }
        Repeater {
          model: root.ready ? Model.categories(root.svc.check) : []
          delegate: ColumnLayout {
            required property var modelData
            property string catKey: modelData.key
            Layout.fillWidth: true
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
                font.bold: true
                color: modelData.good ? root.fg : modelData.ok === 0 ? Color.urgent : root.dim
                text: {
                  var open = !!ov.expanded[catKey]
                  var base = modelData.label + " " + modelData.ok + "/" + modelData.total
                  if (modelData.good) return (open ? "▾ " : "▸ ") + base
                  var hosts = (root.ready && root.svc.check.categories[modelData.key]) ? root.svc.check.categories[modelData.key].results : []
                  var failed = hosts.filter(function(h) { return !h.ok })
                  var quicOnly = failed.length > 0 && failed.every(function(h) { return h.http3 })
                  var reason = quicOnly ? "QUIC не проходит" : (failed.length > 0 ? Model.curlError(failed[0].error) : "не проходит")
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
                  color: modelData.ok ? root.dim : Color.urgent
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

    RowLayout {
      Layout.fillWidth: true
      visible: !sp.editing
      Hint { Layout.fillWidth: true; text: "Не знаете, что выбрать? Запустите «Подбор» — он проверит все стратегии." }
      Button { bordered: true; text: "Обновить из Flowseal"; onClicked: root.svc.updatePresets() }
      Button { bordered: true; text: "Новая стратегия"; onClicked: sp.edit("") }
    }

    ListView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: !sp.editing
      clip: true
      spacing: Style.space(4)
      model: {
        if (!root.ready) return []
        var list = root.svc.presets.slice()
        var rows = Model.autopickRows(root.svc.autopickResult)
        var byPreset = {}
        for (var i = 0; i < rows.length; i++) byPreset[rows[i].preset] = rows[i]
        var order = []
        for (var j = 0; j < list.length; j++) if (order.indexOf(list[j].group) === -1) order.push(list[j].group)
        list.sort(function(a, b) {
          var ga = order.indexOf(a.group), gb = order.indexOf(b.group)
          if (ga !== gb) return ga - gb
          var ra = byPreset[a.name], rb = byPreset[b.name]
          var sa = (ra && (ra.total | 0) > 0) ? ra.score : -1, sb = (rb && (rb.total | 0) > 0) ? rb.score : -1
          if (sa !== sb) return sb - sa
          var ca = (ra && ra.chosen) ? 0 : 1, cb = (rb && rb.chosen) ? 0 : 1
          if (ca !== cb) return ca - cb
          return a.name.localeCompare(b.name, undefined, { numeric: true })
        })
        return list
      }
      section.property: "group"
      section.criteria: ViewSection.FullString
      section.delegate: Label {
        required property string section
        visible: section !== ""
        width: ListView.view.width
        font.bold: true
        color: root.dim
        text: typeof Model.groupTitle === "function" ? Model.groupTitle(section) : section
      }
      delegate: Rectangle {
        required property var modelData
        width: ListView.view.width
        height: row.implicitHeight + Style.space(14)
        radius: Style.cornerRadius
        color: root.ready && root.svc.preset === modelData.name ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
             : hover.hovered ? root.faint : "transparent"
        border.color: root.ready && root.svc.preset === modelData.name ? Color.accent : "transparent"
        HoverHandler { id: hover }
        TapHandler { onTapped: if (root.svc.preset !== modelData.name) root.svc.setOption("preset", modelData.name) }
        RowLayout {
          id: row
          anchors.fill: parent
          anchors.margins: Style.space(7)
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label { Layout.fillWidth: true; text: Model.presetTitle(modelData.name); font.bold: true }
            Hint {
              Layout.fillWidth: true
              text: {
                var rows = Model.autopickRows(root.svc.autopickResult)
                var r = null
                for (var i = 0; i < rows.length; i++) if (rows[i].preset === modelData.name) r = rows[i]
                var parts = []
                if (r && (r.total | 0) > 0) parts.push(r.score + "/" + r.total + " в подборе")
                else if (r && r.error !== "") parts.push(r.error)
                else parts.push("не проверялась")
                if (root.ready && root.svc.preset === modelData.name) parts.push("активна")
                if (r && r.chosen) parts.push("лучшая")
                return parts.join(" · ")
              }
            }
          }
          Button { visible: modelData.name.indexOf("my-") === 0; text: "Изменить"; onClicked: sp.edit(modelData.name) }
          Button {
            visible: modelData.name.indexOf("my-") === 0 && root.svc.preset !== modelData.name
            text: "Удалить"
            onClicked: root.svc.removeCustom(modelData.name)
          }
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
      info = "Загрузка…"
      root.svc.loadText(["list", "show", current], function(r) {
        if (!r.ok) { info = r.message; return }
        listEditor.text = r.data.text + (r.data.text ? "\n" : "")
        info = r.data.count + " записей" + (r.data.truncated ? " (показаны первые 5000)" : "")
      })
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
      Hint { Layout.fillWidth: true; text: lp.info }
      Button { bordered: true; text: "Обновить из Flowseal"; onClicked: root.svc.updateLists() }
    }
    Hint {
      Layout.fillWidth: true
      text: lp.editable ? "По одному домену (поддомены включаются сами) или IP/CIDR на строку. Неверные строки отбрасываются. Сохранение перезапускает обход."
                        : "Встроенный список. Свои записи добавляйте в «Мои …»."
    }
    Editor { id: listEditor; readOnly: !lp.editable }
    RowLayout {
      visible: lp.editable
      Button {
        bordered: true
        text: "Сохранить"
        onClicked: root.svc.saveList(lp.current, listEditor.text, function(r) {
          if (r.ok) { root.svc.flash("Сохранено: " + r.data.count + (r.data.dropped ? ", отброшено " + r.data.dropped : "")); lp.load() }
        })
      }
      Hint { text: Model.countLines(listEditor.text) + " строк" }
    }
  }

  component SearchPage: ScrollView {
    id: se
    property bool showFull: false
    clip: true
    contentWidth: availableWidth
    ColumnLayout {
      width: parent.width
      spacing: Style.space(12)

      Card {
        RowLayout {
          Layout.fillWidth: true
          Label { Layout.fillWidth: true; font.bold: true; text: "Быстрый подбор" }
          Button {
            bordered: true
            text: root.ready && root.svc.busyLabel === "автоподбор" ? "Остановить" : "Запустить"
            onClicked: root.svc.busyLabel === "автоподбор" ? root.svc.stopLong() : root.svc.autopick([])
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
          text: "Без обхода открывается не хуже: в этой сети обход сейчас не нужен"
        }
        Label {
          visible: root.ready && root.svc.progressInfo !== null && root.svc.busyLabel === "автоподбор"
          text: !root.ready || !root.svc.progressInfo ? ""
                : root.svc.progressInfo.step === 0 ? "Замер без обхода…"
                : "Шаг " + root.svc.progressInfo.step + " из " + root.svc.progressInfo.of + ": " + Model.presetTitle(root.svc.progressInfo.preset)
        }
        Repeater {
          model: root.ready ? Model.autopickRows(root.svc.autopickResult) : []
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Label { Layout.preferredWidth: Style.space(180); text: (modelData.chosen ? "● " : "") + modelData.title; font.bold: modelData.chosen }
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(6)
              radius: height / 2
              color: root.faint
              Rectangle { width: parent.width * modelData.pct / 100; height: parent.height; radius: parent.radius; color: modelData.pct === 100 ? Color.accent : root.dim }
            }
            Hint { Layout.preferredWidth: Style.space(160); text: modelData.error !== "" ? modelData.error : modelData.score + "/" + modelData.total; elide: Text.ElideRight; wrapMode: Text.NoWrap }
            // kept in the layout when hidden so every bar has the same length
            Button {
              text: "Выбрать"
              enabled: !modelData.baseline && root.svc.preset !== modelData.preset
              opacity: enabled ? 1 : 0
              onClicked: root.svc.setOption("preset", modelData.preset)
            }
          }
        }
      }

      Card {
        RowLayout {
          Layout.fillWidth: true
          Label { Layout.fillWidth: true; font.bold: true; text: "Глубокий поиск: blockcheck2" }
          Button {
            bordered: true
            text: root.ready && root.svc.blockcheckRunning ? "Остановить" : "Запустить"
            onClicked: root.svc.blockcheckRunning ? root.svc.blockcheckStop()
                       : root.svc.blockcheckStart(domains.text.split(/[\s,]+/).filter(function(d) { return d !== "" }), level.value)
          }
        }
        Hint {
          Layout.fillWidth: true
          text: "Официальный перебор стратегий zapret2. Обход на время поиска выключается. quick — минуты, standard и force — до часа и дольше. Найденное можно сохранить как свою стратегию."
        }
        RowLayout {
          Layout.fillWidth: true
          TextField { id: domains; Layout.fillWidth: true; text: "youtube.com discord.com"; placeholderText: "домены через пробел" }
          Dropdown {
            id: level
            Layout.preferredWidth: Style.space(160)
            showLabel: false
            value: "quick"
            options: [{ value: "quick", label: "quick" }, { value: "standard", label: "standard" }, { value: "force", label: "force" }]
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
          text: root.ready && root.svc.blockcheck ? (root.svc.blockcheck.done ? "Готово. " : root.svc.blockcheckRunning ? "Идёт поиск… " : "")
                + root.svc.blockcheck.lines + " строк журнала" : ""
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
    ColumnLayout {
      width: parent.width
      spacing: Style.space(12)

      Card {
        Label { font.bold: true; text: "Движок: " + (root.ready && root.svc.st && root.svc.st.engine ? root.svc.st.engine : "не установлен") }
        Hint { Layout.fillWidth: true; text: "bol-van/zapret2: nfqws2 + Lua. Обновление скачивает последний релиз, сверяет sha256 и спрашивает пароль. Предыдущая версия остаётся рядом." }
        RowLayout {
          Button { bordered: true; text: "Обновить движок"; enabled: root.ready && root.svc.installed; onClicked: root.svc.engineUpdate() }
          Button { bordered: true; text: "Обновить системную часть"; enabled: root.ready && root.svc.installed; onClicked: root.svc.updateApp() }
        }
      }

      Card {
        RowLayout {
          Layout.fillWidth: true
          Label { Layout.fillWidth: true; font.bold: true; text: "Диагностика" }
          Button { text: "Повторить"; onClicked: root.svc.runDoctor() }
        }
        Repeater {
          model: root.ready ? root.svc.doctorItems : []
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Label { Layout.preferredWidth: Style.space(170); text: (modelData.ok ? "✓ " : "✗ ") + modelData.name; color: modelData.ok ? root.fg : Color.urgent }
            Hint { Layout.fillWidth: true; text: modelData.detail }
          }
        }
      }

      Card {
        RowLayout {
          Layout.fillWidth: true
          Label { Layout.fillWidth: true; font.bold: true; text: "Журнал службы" }
          Button { text: "Обновить"; onClicked: root.svc.loadLogs() }
        }
        Hint { visible: root.ready && root.svc.logNote !== ""; Layout.fillWidth: true; text: root.ready ? root.svc.logNote : "" }
        Editor {
          Layout.preferredHeight: Style.space(240)
          Layout.fillHeight: false
          readOnly: true
          text: root.ready ? root.svc.logLines.join("\n") : ""
        }
      }

      Card {
        visible: root.ready && root.svc.installed
        Label { font.bold: true; text: "Удаление" }
        Hint { Layout.fillWidth: true; text: "Останавливает обход и удаляет всё, что поставила установка: /opt/omarchy-zapret2, юниты, правило polkit. Ваши списки и стратегии в /var/lib/omarchy-zapret2 остаются, если не выбрать «вместе с данными»." }
        RowLayout {
          Button { bordered: true; text: ep.armRemove ? "Точно удалить?" : "Удалить"; onClicked: { if (ep.armRemove) { ep.armRemove = false; root.svc.removeAll(false) } else ep.armRemove = true } }
          Button { visible: ep.armRemove; text: "Вместе с данными"; onClicked: { ep.armRemove = false; root.svc.removeAll(true) } }
          Button { visible: ep.armRemove; text: "Отмена"; onClicked: ep.armRemove = false }
        }
      }
    }
  }

  component SettingsPage: ScrollView {
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
          ToggleSwitch { checked: root.ready && root.svc.settings.autostart === true; onToggled: root.svc.setOption("autostart", checked ? "off" : "on") }
        }
        RowLayout {
          Layout.fillWidth: true
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label { Layout.fillWidth: true; font.bold: true; text: "IPv6" }
            Hint { Layout.fillWidth: true; text: "Обрабатывать и IPv6-соединения" }
          }
          ToggleSwitch { checked: root.ready && root.svc.settings.ipv6 !== false; onToggled: root.svc.setOption("ipv6", checked ? "off" : "on") }
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
        RowLayout {
          Layout.fillWidth: true
          visible: root.ready && (root.svc.settings.game || "off") !== "off"
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
        Dropdown {
          Layout.fillWidth: true
          label: "Фейк для голоса Discord"
          value: root.ready ? (root.svc.settings.discordFake || "default") : "default"
          options: (root.ready && root.svc.fakeChoices ? root.svc.fakeChoices : ["default"]).map(function(n) {
            return { value: n, label: n === "default" ? "По умолчанию" : String(n).replace(/^fs_/, "") }
          })
          onChanged: function(v) { root.svc.setOption("discordfake", v) }
        }
        Dropdown {
          Layout.fillWidth: true
          label: "Фейк для игр"
          value: root.ready ? (root.svc.settings.gameFake || "default") : "default"
          options: (root.ready && root.svc.fakeChoices ? root.svc.fakeChoices : ["default"]).map(function(n) {
            return { value: n, label: n === "default" ? "По умолчанию" : String(n).replace(/^fs_/, "") }
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
            onToggled: root.svc.hostsSet(!root.svc.hostsOn)
          }
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
          text: "Добавьте в ~/.config/hypr/bindings.lua, например:\n"
              + "omarchy-shell krieziey.omarchy-zapret2 toggle — окно приложения\n"
              + "omarchy-shell krieziey.omarchy-zapret2 toggleBypass — включить/выключить обход"
        }
      }
    }
  }
}
