import QtQuick
import qs.Commons

/*
 * Shield drawn with Canvas primitives (no font, no SVG): outline when off,
 * filled with a cut-out check when on, a badge dot on errors. 24-unit grid.
 */
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool filled: false
  property bool warning: false
  property color badgeColor: Color.urgent

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  onColorChanged: canvas.requestPaint()
  onFilledChanged: canvas.requestPaint()
  onWarningChanged: canvas.requestPaint()
  onBadgeColorChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    onWidthChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var k = width / 24
      ctx.lineWidth = Math.max(1.2, 1.6 * k)
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

      if (root.warning) {
        ctx.fillStyle = root.badgeColor
        ctx.beginPath()
        ctx.arc(19.5 * k, 19.5 * k, 3.5 * k, 0, Math.PI * 2)
        ctx.fill()
      }
    }
  }
}
