import QtQuick
import qs.Commons
import qs.Ui

/*
 * Breach mark: a brick wall on a ground line with an arched opening, the
 * sibling of omarchy-xray's tunnel (same 24-unit grid, stroke and ground).
 * Off: outline. On: a solid wall with the joints and the breach cut out.
 * At bar size (`simple`) the joints are dropped so the opening stays clear.
 * Errors get a badge dot with a contrasting "!".
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
      ctx.lineWidth = Math.max(1.2, 1.5 * k)
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.strokeStyle = root.color
      ctx.fillStyle = root.color
      ctx.translate(0, -1.1 * k)   // same lift as the xray tunnel

      function wall() { ctx.beginPath(); ctx.rect(4.5 * k, 6 * k, 15 * k, 12.5 * k) }
      function joints() {
        ctx.beginPath()
        ctx.moveTo(4.5 * k, 10 * k); ctx.lineTo(19.5 * k, 10 * k)
        if (root.simple) return
        ctx.moveTo(4.5 * k, 14 * k); ctx.lineTo(9 * k, 14 * k)
        ctx.moveTo(15 * k, 14 * k); ctx.lineTo(19.5 * k, 14 * k)
        ctx.moveTo(9 * k, 6 * k); ctx.lineTo(9 * k, 10 * k)
        ctx.moveTo(15 * k, 6 * k); ctx.lineTo(15 * k, 10 * k)
      }
      function breach() {
        ctx.beginPath()
        ctx.moveTo(9 * k, 18.5 * k)
        ctx.lineTo(9 * k, 14.5 * k)
        ctx.arc(12 * k, 14.5 * k, 3 * k, Math.PI, 0, false)
        ctx.lineTo(15 * k, 18.5 * k)
      }

      if (root.filled) {
        wall(); ctx.fill()
        ctx.globalCompositeOperation = "destination-out"
        joints(); ctx.stroke()
        breach(); ctx.closePath(); ctx.fill(); ctx.stroke()
        ctx.globalCompositeOperation = "source-over"
      } else {
        ctx.beginPath()
        ctx.moveTo(4.5 * k, 18.5 * k); ctx.lineTo(4.5 * k, 6 * k)
        ctx.lineTo(19.5 * k, 6 * k); ctx.lineTo(19.5 * k, 18.5 * k)
        ctx.stroke()
        joints(); ctx.stroke()
        breach(); ctx.stroke()
      }
      ctx.beginPath(); ctx.moveTo(2 * k, 21 * k); ctx.lineTo(22 * k, 21 * k); ctx.stroke()   // ground
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
