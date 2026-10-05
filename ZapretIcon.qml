import QtQuick
import qs.Commons
import qs.Ui

/*
 * Shield drawn with Canvas primitives (no font, no SVG): outline when off,
 * filled with a cut-out check when on. At bar size (`simple`) the outline is
 * drawn heavier and on/off reads from the button dimming instead of the
 * fill. Errors get a badge dot with a contrasting "!" on a
 * popup-background ring. 24-unit grid.
 */
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool filled: false
  property bool warning: false
  // Bar size: a heavier outline reads better at 14px than a filled shield.
  property bool simple: false
  property color badgeColor: Color.urgent

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  onColorChanged: canvas.requestPaint()
  onFilledChanged: canvas.requestPaint()
  onSimpleChanged: canvas.requestPaint()
  onBadgeColorChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var k = width / 24
      ctx.lineWidth = Math.max(1.2, (root.simple ? 1.9 : 1.6) * k)
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.strokeStyle = root.color
      ctx.fillStyle = root.color

      ctx.beginPath()
      ctx.moveTo(12 * k, 2.5 * k)
      ctx.lineTo(20 * k, 5.5 * k)
      ctx.lineTo(20 * k, 11 * k)
      ctx.bezierCurveTo(20 * k, 16 * k, 16.5 * k, 19.5 * k, 12 * k, 21.5 * k)
      ctx.bezierCurveTo(7.5 * k, 19.5 * k, 4 * k, 16 * k, 4 * k, 11 * k)
      ctx.lineTo(4 * k, 5.5 * k)
      ctx.closePath()
      if (root.filled) {
        ctx.fill()
        ctx.globalCompositeOperation = "destination-out"
        ctx.lineWidth = Math.max(1.4, 2 * k)
        ctx.beginPath()
        ctx.moveTo(8.5 * k, 12 * k)
        ctx.lineTo(11 * k, 14.5 * k)
        ctx.lineTo(15.5 * k, 9.5 * k)
        ctx.stroke()
        ctx.globalCompositeOperation = "source-over"
      } else {
        ctx.stroke()
      }
    }
  }

  BorderSurface {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    borderSpec: Border.flat(Color.popups.background, 1)

    Text {
      anchors.centerIn: parent
      text: "!"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
