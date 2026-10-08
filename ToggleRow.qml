import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "model/Zapret.js" as Model

// Toggle row in its own outline: label on the left, switch on the right,
// dim one-line description below. The outline ties each switch to its label.
// Clicking the label flips too (a small switch is a small target).
BorderSurface {
  id: root

  property string label: ""
  property string a11yName: ""
  property string note: ""
  property bool checked: false
  property bool usable: true
  property bool busy: false
  property bool hasCursor: false
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  signal flip()

  Layout.fillWidth: true
  implicitHeight: body.implicitHeight + Style.space(16)
  color: "transparent"
  // Nested inside a section box: a quieter outline than the section.
  borderSpec: Border.flat(Model.mixColor(root.foreground, Color.popups.background, 0.78), 1)
  radius: Style.cornerRadius

  ColumnLayout {
  id: body
  anchors.fill: parent
  anchors.margins: Style.space(8)
  anchors.leftMargin: Style.space(12)
  anchors.rightMargin: Style.space(12)
  spacing: Style.space(2)

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(8)

    Text {
      id: rowLabel
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      textFormat: Text.PlainText
      text: root.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      Accessible.role: Accessible.CheckBox
      Accessible.name: root.a11yName !== "" ? root.a11yName : root.label
      Accessible.description: root.note
      Accessible.checked: root.checked
      MouseArea {
        id: labelHover
        anchors.fill: parent
        anchors.topMargin: -Style.space(6)
        anchors.bottomMargin: -Style.space(6)
        hoverEnabled: true
        enabled: root.usable
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.usable) root.flip()
      }
    }

    ToggleSwitch {
      id: rowSwitch
      trackHeight: Math.round(Style.font.caption * 1.2)
      cursorPad: Style.space(3)
      Layout.alignment: Qt.AlignVCenter
      checked: root.checked
      hasCursor: root.hasCursor
      opacity: root.usable && !root.busy ? 1.0 : 0.45
      foreground: root.foreground
      onToggled: if (root.usable) root.flip()
      onHovered: function(h) {}
      Accessible.role: Accessible.CheckBox
      Accessible.name: root.a11yName !== "" ? root.a11yName : root.label
      Accessible.description: root.note
      Accessible.checked: root.checked
      Accessible.focusable: true
      Accessible.focused: root.hasCursor
    }
  }

  Text {
    visible: text !== ""
    Layout.fillWidth: true
    textFormat: Text.PlainText
    text: root.note
    color: Model.mixColor(root.foreground, Color.popups.background, 0.34)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
    elide: Text.ElideRight
    maximumLineCount: 1
  }
}
}
