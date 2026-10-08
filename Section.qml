import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "model/Zapret.js" as Model

// Section: a small uppercase header line with optional dim trailing note and
// optional right-side text actions, plus an outlined box holding the content.
// Rows inside carry their own outline too.
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
      elide: Text.ElideRight
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

  BorderSurface {
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + Style.space(20)
    color: "transparent"
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
    radius: Style.cornerRadius

    ColumnLayout {
      id: body
      anchors.fill: parent
      anchors.margins: Style.space(10)
      spacing: Style.space(6)
    }
  }
}
