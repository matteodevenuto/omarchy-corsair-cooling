import QtQuick
import qs.Commons

// A ring of LEDs animated like corsair-rgbd renders them.
// ponytail: JS mirror of corsair-rgbd's pixel(); keep the two in step when adding effects.
Item {
  id: ring

  property var zone: ({})          // {effect, color, brightness, speed}
  property var theme: ({ accent: "ffffff", palette: [] })
  property real coolant: 0
  property real time: 0
  property int count: 8
  property real dot: Style.space(7)
  property string label: ""
  property color labelColor: Color.foreground
  property string fontFamily: Style.font.family

  function hex(value) {
    var v = String(value || "ffffff")
    return [parseInt(v.substr(0, 2), 16) / 255, parseInt(v.substr(2, 2), 16) / 255, parseInt(v.substr(4, 2), 16) / 255]
  }

  function hsv(h, s, v) {
    var c = Qt.hsva(((h % 1) + 1) % 1, s, v, 1)
    return [c.r, c.g, c.b]
  }

  function pixel(i, n) {
    var z = zone || {}
    var color = hex(z.color === "theme" ? theme.accent : z.color)
    var phase = time * (z.speed || 5) / 10
    var pos = i / Math.max(n, 1)
    var scale = function(k) { return color.map(function(c) { return c * k }) }
    switch (z.effect) {
    case "off": return [0, 0, 0]
    case "temperature":
      return hsv(0.66 * (1 - Math.max(0, Math.min(1, (coolant - 30) / 15))), 1, 1)
    case "wave": return scale(0.55 + 0.45 * Math.sin(2 * Math.PI * (pos - phase)))
    case "breathing": return scale(0.5 - 0.5 * Math.cos(phase * 2 * Math.PI))
    case "spectrum": return hsv(phase / 4, 1, 1)
    case "rainbow": return hsv(pos - phase / 2, 1, 1)
    case "spinner":
      var behind = (((phase * n - i) % n) + n) % n
      var glow = Math.max(1 - behind / (n / 2), behind - (n - 1))
      return scale(0.3 + 0.7 * Math.pow(Math.max(0, glow), 1.5))
    case "palette":
      var p = (theme.palette && theme.palette.length) ? theme.palette : ["ff0000", "ffff00", "00ff00", "00ffff", "0000ff", "ff00ff"]
      var x = ((((pos - phase / 2) % 1) + 1) % 1) * p.length
      var a = hex(p[Math.floor(x) % p.length]), b = hex(p[(Math.floor(x) + 1) % p.length]), f = x % 1
      return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f]
    }
    return color
  }

  implicitWidth: Style.space(84)
  implicitHeight: width + caption.implicitHeight + Style.space(6)

  Item {
    id: circle
    width: ring.width
    height: width

    Repeater {
      model: ring.count
      delegate: Rectangle {
        required property int index
        readonly property real angle: -Math.PI / 2 + 2 * Math.PI * index / ring.count
        readonly property var rgb: ring.pixel(index, ring.count)
        readonly property real k: (ring.zone && ring.zone.brightness !== undefined ? ring.zone.brightness : 100) / 100
        width: ring.dot
        height: width
        radius: width / 2
        x: circle.width / 2 + Math.cos(angle) * (circle.width / 2 - ring.dot) - width / 2
        y: circle.height / 2 + Math.sin(angle) * (circle.height / 2 - ring.dot) - height / 2
        color: Qt.rgba(rgb[0] * k, rgb[1] * k, rgb[2] * k, 1)
        border.width: 1
        border.color: Qt.rgba(ring.labelColor.r, ring.labelColor.g, ring.labelColor.b, 0.12)

        // Soft glow so dim LEDs still read as LEDs
        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 2.2
          height: width
          radius: width / 2
          z: -1
          color: Qt.rgba(parent.rgb[0], parent.rgb[1], parent.rgb[2], 0.18 * parent.k)
        }
      }
    }
  }

  Text {
    id: caption
    anchors.top: circle.bottom
    anchors.topMargin: Style.space(6)
    anchors.horizontalCenter: parent.horizontalCenter
    text: ring.label
    color: Qt.darker(ring.labelColor, 1.4)
    font.family: ring.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.1
  }
}
