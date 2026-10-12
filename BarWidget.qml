import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Commander CORE readout in the bar (styled like meviusisback.hw-monitor's
// temperature cell) plus a tabbed panel: overview, fan curves and lighting.
Panel {
  id: root

  moduleName: "matteodevenuto.corsair-cooling"
  ipcTarget: "matteodevenuto.corsair-cooling"
  manageIpc: false

  readonly property string helperPath:
    Qt.resolvedUrl("corsair-cooling").toString().replace(/^file:\/\//, "")
  readonly property bool vertical: bar ? bar.vertical : false

  // Telemetry
  property bool connected: false
  property bool loading: false
  property bool applying: false
  property string errorText: ""
  property real waterTemp: -1
  property int pumpRpm: -1
  property var fans: []
  property var coolantHistory: []  // from corsair-rgbd (6 min), else one sample per manual read

  // Cooling profile last applied through the panel
  property string profileName: ""
  property int profilePump: 0
  property var profileCurve: []

  // Lighting, mirrored from corsair-rgbd's config
  property bool rgbdRunning: false
  property var lighting: ({})

  // Bar look (shared with hw-monitor)
  readonly property int iconSize: Style.bar.iconFont
  readonly property int valueSize: Math.max(9, Math.round(iconSize * 0.92))
  readonly property int contentHeight: Math.max(Math.max(Style.bar.iconCanvas, iconSize + Style.space(2)), Style.space(15))
  readonly property color base: bar ? bar.barForeground : Color.foreground
  readonly property color hot: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(base, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Same as hw-monitor's warm(): blend toward urgent as coolant heats past 40 °C (full at 45 °C).
  readonly property real heat: waterTemp > 40 ? Math.min(1, (waterTemp - 40) / 5) : 0
  function warm(from) {
    return Qt.rgba(from.r + (hot.r - from.r) * heat, from.g + (hot.g - from.g) * heat,
                   from.b + (hot.b - from.b) * heat, from.a)
  }

  function refresh(cached) {
    if (statusProc.running || applying) return
    loading = true
    statusProc.cached = cached === true
    statusProc.command = [helperPath, statusProc.cached ? "cached" : "status"]
    statusProc.running = true
  }

  function applyStatus(raw) {
    var payload = null
    try { payload = JSON.parse(String(raw || "")) } catch (e) {}
    if (!Array.isArray(payload) || payload.length === 0 || !Array.isArray(payload[0].status)) {
      connected = false
      errorText = "Commander CORE status unavailable"
      return
    }
    var nextFans = []
    var temp = -1
    var pump = -1
    var rows = payload[0].status
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i] || {}
      var key = String(row.key || "")
      var value = Number(row.value)
      if (key === "Pump speed") pump = Math.round(value)
      else if (key === "Water temperature") temp = value
      else if (/^Fan speed [1-6]$/.test(key))
        nextFans.push({ name: key.replace(" speed", ""), rpm: Math.round(value) })
    }
    connected = true
    errorText = ""
    waterTemp = temp
    pumpRpm = pump
    fans = nextFans
    if (Array.isArray(payload[0].history)) coolantHistory = payload[0].history
    else if (temp > 0) coolantHistory = coolantHistory.concat([temp]).slice(-120)
  }

  // points: [[temp, duty], ...]
  function applyProfile(name, pump, points) {
    if (applying) return
    applying = true
    errorText = ""
    var cmd = [helperPath, "apply", name, String(pump)]
    for (var i = 0; i < points.length; i++)
      cmd.push(String(Math.round(points[i][0])), String(Math.round(points[i][1])))
    actionProc.label = name
    actionProc.command = cmd
    actionProc.running = true
  }

  function initializeDevice() {
    if (applying) return
    applying = true
    errorText = ""
    actionProc.label = "Initialize"
    actionProc.command = [helperPath, "initialize"]
    actionProc.running = true
  }

  function setLighting(zone, effect, color, brightness, speed) {
    var next = JSON.parse(JSON.stringify(lighting))
    var zones = zone === "all" ? ["aio", "fans"] : [zone]
    for (var i = 0; i < zones.length; i++)
      next[zones[i]] = { effect: effect, color: color, brightness: brightness, speed: speed }
    lighting = next
    lightProc.running = false
    lightProc.command = [helperPath, "lighting", zone, effect, color, String(brightness), String(speed)]
    lightProc.running = true
  }

  function reloadConfig() {
    lightProc.running = false
    lightProc.command = [helperPath, "lighting"]
    lightProc.running = true
    coolingProc.running = true
  }

  function parseJson(text) {
    try { return JSON.parse(String(text || "")) } catch (e) { return null }
  }

  Process {
    id: statusProc
    property bool cached: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (!statusProc.cached || String(text || "") !== "") root.applyStatus(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.errorText = String(text).trim()
    }
    onExited: function(exitCode) {
      root.loading = false
      if (statusProc.cached) root.rgbdRunning = exitCode === 0
      else if (exitCode !== 0) root.connected = false
    }
  }

  Process {
    id: actionProc
    property string label: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = root.parseJson(text)
        if (result && result.ok === false) root.errorText = result.error
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.errorText = String(text).trim()
    }
    onExited: function(exitCode) {
      root.applying = false
      if (exitCode === 0) {
        root.errorText = ""
        coolingProc.running = true
        Qt.callLater(root.refresh, true)
      } else if (root.errorText === "") {
        root.errorText = "Could not apply " + actionProc.label
      }
    }
  }

  Process {
    id: coolingProc
    command: [root.helperPath, "cooling"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cfg = root.parseJson(text)
        if (!cfg || !cfg.profile) return
        root.profileName = cfg.profile
        root.profilePump = cfg.pump
        root.profileCurve = cfg.curve
      }
    }
  }

  Process {
    id: lightProc
    command: [root.helperPath, "lighting"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cfg = root.parseJson(text)
        if (cfg && cfg.ok === false) root.errorText = cfg.error
        else if (cfg && cfg.aio) root.lighting = cfg
      }
    }
  }

  // Reads corsair-rgbd's cache only: never touches USB, so it never flashes the RGB.
  Timer {
    interval: 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh(true)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 6
    active: root.opened
    tooltipText: root.connected
      ? "Coolant " + root.waterTemp.toFixed(1) + "°C · pump " + root.pumpRpm + " RPM"
      : (root.rgbdRunning ? "Corsair cooling · connecting…" : "Corsair cooling · middle-click to read")
    fixedWidth: root.vertical ? -1 : Math.ceil(cell.implicitWidth + button.scaledHorizontalMargin * 2)
    fixedHeight: root.vertical ? Math.ceil(cell.implicitHeight + Style.space(8)) : -1

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }

    Row {
      id: cell
      anchors.centerIn: parent
      spacing: Style.space(4)

      TextMetrics {
        id: glyphMetrics
        font.family: root.fontFamily
        font.pixelSize: root.iconSize
        text: "󰈐"
      }

      Item {
        width: Math.max(1, Math.ceil(glyphMetrics.tightBoundingRect.width))
        height: root.contentHeight

        OpticalGlyph {
          anchors.fill: parent
          text: "󰈐"
          fontFamily: root.fontFamily
          fontSize: root.iconSize
          color: root.connected ? root.warm(Color.accent) : root.dim
          Behavior on color { ColorAnimation { duration: 240 } }
        }
      }

      Text {
        visible: !root.vertical
        height: root.contentHeight
        text: root.waterTemp > 0 ? Math.round(root.waterTemp) + "°" : "–"
        color: root.connected ? root.warm(root.base) : root.dim
        font.family: root.fontFamily
        font.pixelSize: root.valueSize
        font.bold: true
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
        Behavior on color { ColorAnimation { duration: 240 } }
      }
    }
  }

  CoolingPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    widget: root
  }

  IpcHandler {
    target: "matteodevenuto.corsair-cooling"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    // overview | cooling | lighting
    function openTab(name: string): void { panel.tab = name; root.open() }
    function lighting(zone: string, effect: string, color: string, brightness: int, speed: int): void {
      root.setLighting(zone, effect, color, brightness, speed)
    }
    function status(): string {
      return JSON.stringify({
        connected: root.connected,
        coolantC: root.waterTemp,
        pumpRpm: root.pumpRpm,
        fans: root.fans,
        profile: root.profileName,
        lighting: root.lighting,
        rgbd: root.rgbdRunning,
        applying: root.applying,
        error: root.errorText
      })
    }
  }
}
