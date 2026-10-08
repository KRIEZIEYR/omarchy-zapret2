import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "model/Zapret.js" as Model

// Flat section: a small uppercase header line with optional dim trailing note
// and optional right-side text actions, plus content below. Sections are NOT
// boxed: callers divide them with a PanelSeparator. Mirrors the omarchy-xray
// panel language (SectionTitle header row without the box).
ColumnLayout {
  id: root

  property string title: ""
  property string trailing: ""
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family
  property alias actions: actionRow.data
  default property alias content: body.data

  Layout.fillWidth: true
  spacing: Style.space(6)

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(8)

    PanelSectionHeader {
      Layout.fillWidth: true
      text: root.title
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      visible: text !== ""
      Layout.alignment: Qt.AlignVCenter
      textFormat: Text.PlainText
      text: root.trailing
      color: Model.mixColor(root.foreground, Color.popups.background, 0.34)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    RowLayout {
      id: actionRow
      spacing: Style.space(12)
    }
  }

  ColumnLayout {
    id: body
    Layout.fillWidth: true
    spacing: Style.space(6)
  }
}
