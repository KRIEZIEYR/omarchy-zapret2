import QtQuick
import qs.Commons
import qs.Ui

/*
 * Open padlock: body with a keyhole, shackle swung open. Off: outline.
 * On: solid body with the keyhole cut out. 24-unit grid, same stroke as the
 * xray tunnel. Errors get a badge dot with a contrasting "!".
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
      ctx.lineWidth = Math.max(1.2, (root.simple ? 1.8 : 1.5) * k)
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.strokeStyle = root.color
      ctx.fillStyle = root.color
      ctx.translate(0, -1 * k)   // the drawing sits low; centre it

      function body() {
        var x = 5 * k, y = 11 * k, w = 14 * k, h = 10 * k, r = 2 * k
        ctx.beginPath()
        ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y)
        ctx.arcTo(x + w, y, x + w, y + r, r); ctx.lineTo(x + w, y + h - r)
        ctx.arcTo(x + w, y + h, x + w - r, y + h, r); ctx.lineTo(x + r, y + h)
        ctx.arcTo(x, y + h, x, y + h - r, r); ctx.lineTo(x, y + r)
        ctx.arcTo(x, y, x + r, y, r); ctx.closePath()
      }
      function keyhole() { ctx.beginPath(); ctx.moveTo(12 * k, 15 * k); ctx.lineTo(12 * k, 17 * k) }

      // shackle: up from the right side of the body, over, open on the left
      ctx.beginPath()
      ctx.moveTo(16 * k, 11 * k); ctx.lineTo(16 * k, 7 * k)
      ctx.arc(12 * k, 7 * k, 4 * k, 0, -2.70, true)
      ctx.stroke()

      if (root.filled) {
        body(); ctx.fill()
        ctx.globalCompositeOperation = "destination-out"
        ctx.lineWidth = Math.max(1.4, 2 * k)
        keyhole(); ctx.stroke()
        ctx.globalCompositeOperation = "source-over"
      } else {
        body(); ctx.stroke()
        keyhole(); ctx.stroke()
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
