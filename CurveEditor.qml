import QtQuick
import QtQuick.Shapes
import qs.Commons

// Fan duty vs coolant temperature.  Drag points to edit, double-click the graph
// to add one (max 7), right-click a point to remove it.  Edits keep the curve
// valid for the helper: temperatures rise, duty never falls, and the last
// point is pinned at 100 % so full cooling is always reachable.
Item {
  id: ed

  property var points: []      // [[tempC, duty], ...]
  property var reference: []   // curve currently on the controller, drawn faint
  property real coolant: -1
  property color baseColor: Color.foreground
  property color lineColor: Color.accent
  property color hotColor: Color.urgent
  property string fontFamily: Style.font.family
  signal edited(var points)

  readonly property int tMin: 20
  readonly property int tMax: 60
  readonly property int dMin: 20
  readonly property real padL: Style.space(30)
  readonly property real padB: Style.space(18)
  readonly property real padT: Style.space(8)
  readonly property real padR: Style.space(10)
  readonly property real plotW: width - padL - padR
  readonly property real plotH: height - padT - padB

  function xOf(t) { return padL + (t - tMin) / (tMax - tMin) * plotW }
  function yOf(d) { return padT + (1 - d / 100) * plotH }

  function dutyAt(pts, t) {
    if (!pts || pts.length === 0) return 0
    if (t <= pts[0][0]) return pts[0][1]
    for (var i = 1; i < pts.length; i++) {
      if (t <= pts[i][0]) {
        var a = pts[i - 1], b = pts[i]
        return a[1] + (b[1] - a[1]) * (t - a[0]) / (b[0] - a[0])
      }
    }
    return pts[pts.length - 1][1]
  }

  // Flat before the first point and after the last, like the controller.
  function polyline(pts) {
    if (!pts || pts.length === 0) return []
    var out = [Qt.point(xOf(tMin), yOf(pts[0][1]))]
    for (var i = 0; i < pts.length; i++) out.push(Qt.point(xOf(pts[i][0]), yOf(pts[i][1])))
    out.push(Qt.point(xOf(tMax), yOf(pts[pts.length - 1][1])))
    return out
  }

  function moved(index, x, y) {
    var pts = points.map(function(p) { return [p[0], p[1]] })
    var last = index === pts.length - 1
    var t = Math.round(tMin + (x - padL) / plotW * (tMax - tMin))
    var d = last ? 100 : Math.round(100 * (1 - (y - padT) / plotH))
    t = Math.max(index > 0 ? pts[index - 1][0] + 1 : tMin, Math.min(index < pts.length - 1 ? pts[index + 1][0] - 1 : tMax, t))
    d = Math.max(index > 0 ? pts[index - 1][1] : dMin, Math.min(index < pts.length - 1 ? pts[index + 1][1] : 100, d))
    pts[index] = [t, d]
    edited(pts)
  }

  function insertAt(x) {
    if (points.length >= 7) return
    var t = Math.round(tMin + (x - padL) / plotW * (tMax - tMin))
    var pts = points.map(function(p) { return [p[0], p[1]] })
    for (var i = 0; i < pts.length; i++) if (pts[i][0] === t) return
    if (t >= pts[pts.length - 1][0]) return  // the pinned 100 % point stays last
    pts.push([t, Math.max(dMin, Math.round(dutyAt(points, t)))])
    pts.sort(function(a, b) { return a[0] - b[0] })
    edited(pts)
  }

  function removeAt(index) {
    if (points.length <= 2 || index === points.length - 1) return
    var pts = points.map(function(p) { return [p[0], p[1]] })
    pts.splice(index, 1)
    edited(pts)
  }

  // Grid
  Repeater {
    model: [20, 30, 40, 50, 60]
    delegate: Item {
      required property int modelData
      Rectangle {
        x: ed.xOf(modelData)
        y: ed.padT
        width: 1
        height: ed.plotH
        color: Qt.rgba(ed.baseColor.r, ed.baseColor.g, ed.baseColor.b, 0.08)
      }
      Text {
        x: ed.xOf(modelData) - width / 2
        y: ed.padT + ed.plotH + Style.space(3)
        text: modelData + "°"
        color: Qt.darker(ed.baseColor, 1.4)
        font.family: ed.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Repeater {
    model: [25, 50, 75, 100]
    delegate: Item {
      required property int modelData
      Rectangle {
        x: ed.padL
        y: ed.yOf(modelData)
        width: ed.plotW
        height: 1
        color: Qt.rgba(ed.baseColor.r, ed.baseColor.g, ed.baseColor.b, 0.08)
      }
      Text {
        x: ed.padL - width - Style.space(5)
        y: ed.yOf(modelData) - height / 2
        text: modelData + "%"
        color: Qt.darker(ed.baseColor, 1.4)
        font.family: ed.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    // Fill under the draft curve
    ShapePath {
      strokeColor: "transparent"
      fillColor: Qt.rgba(ed.lineColor.r, ed.lineColor.g, ed.lineColor.b, 0.10)
      PathPolyline {
        path: {
          var line = ed.polyline(ed.points)
          if (line.length === 0) return []
          return line.concat([Qt.point(ed.xOf(ed.tMax), ed.yOf(0)), Qt.point(ed.xOf(ed.tMin), ed.yOf(0))])
        }
      }
    }

    // Curve stored on the controller
    ShapePath {
      strokeWidth: 1.5
      strokeColor: Qt.rgba(ed.baseColor.r, ed.baseColor.g, ed.baseColor.b, 0.35)
      strokeStyle: ShapePath.DashLine
      dashPattern: [3, 3]
      fillColor: "transparent"
      PathPolyline { path: ed.polyline(ed.reference) }
    }

    // Draft curve
    ShapePath {
      strokeWidth: 2
      strokeColor: ed.lineColor
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      PathPolyline { path: ed.polyline(ed.points) }
    }
  }

  // Live coolant marker
  Item {
    visible: ed.coolant >= ed.tMin && ed.coolant <= ed.tMax
    anchors.fill: parent

    Rectangle {
      x: ed.xOf(ed.coolant)
      y: ed.padT
      width: 1
      height: ed.plotH
      color: Qt.rgba(ed.hotColor.r, ed.hotColor.g, ed.hotColor.b, 0.6)
    }
    Rectangle {
      width: Style.space(9)
      height: width
      radius: width / 2
      x: ed.xOf(ed.coolant) - width / 2
      y: ed.yOf(ed.dutyAt(ed.points, ed.coolant)) - height / 2
      color: ed.hotColor
      Behavior on y { NumberAnimation { duration: 240 } }
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onDoubleClicked: function(mouse) { ed.insertAt(mouse.x) }
  }

  Repeater {
    model: ed.points.length
    delegate: Rectangle {
      id: handle
      required property int index
      readonly property bool pinned: index === ed.points.length - 1
      readonly property bool hot: dragArea.containsMouse || dragArea.pressed
      width: Style.space(hot ? 13 : 11)
      height: width
      radius: width / 2
      x: ed.xOf(ed.points[index][0]) - width / 2
      y: ed.yOf(ed.points[index][1]) - height / 2
      color: hot ? ed.lineColor : Color.background
      border.width: 2
      border.color: ed.lineColor
      Behavior on width { NumberAnimation { duration: 100 } }

      MouseArea {
        id: dragArea
        anchors.fill: parent
        anchors.margins: -Style.space(5)
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: handle.pinned ? Qt.SizeHorCursor : Qt.SizeAllCursor
        preventStealing: true
        onClicked: function(mouse) { if (mouse.button === Qt.RightButton) ed.removeAt(handle.index) }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var p = mapToItem(ed, mouse.x, mouse.y)
          ed.moved(handle.index, p.x, p.y)
        }
      }

      Rectangle {
        visible: handle.hot
        anchors.bottom: parent.top
        anchors.bottomMargin: Style.space(4)
        anchors.horizontalCenter: parent.horizontalCenter
        width: tip.implicitWidth + Style.space(8)
        height: tip.implicitHeight + Style.space(4)
        radius: Style.cornerRadius
        color: Color.tooltip.background
        Text {
          id: tip
          anchors.centerIn: parent
          text: ed.points[handle.index][0] + "°C · " + ed.points[handle.index][1] + "%"
          color: Color.tooltip.text
          font.family: ed.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
