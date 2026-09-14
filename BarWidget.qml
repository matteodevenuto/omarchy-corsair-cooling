import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "matteodevenuto.corsair-cooling"
  ipcTarget: "matteodevenuto.corsair-cooling"

  readonly property string helperPath:
    Qt.resolvedUrl("corsair-cooling").toString().replace(/^file:\/\//, "")
  property bool connected: false
  property bool loading: false
  property bool applying: false
  property string errorText: ""
  property string pendingPreset: ""
  property string lastProfile: "Not changed this session"
  property real waterTemp: -1
  property int pumpRpm: -1
  property var fans: []

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int barSlot: Style.space(62)

  function faded(color, amount) {
    var bg = Color.background
    return Qt.rgba(color.r + (bg.r - color.r) * amount,
                   color.g + (bg.g - color.g) * amount,
                   color.b + (bg.b - color.b) * amount, 1)
  }

  readonly property color muted: faded(foreground, 0.55)
  readonly property color temperatureColor: waterTemp >= 43 ? urgent
    : waterTemp >= 40 ? "#e5a84b" : foreground

  implicitWidth: bar && bar.vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  function refresh() {
    if (statusProc.running || applying) return
    loading = true
    statusProc.command = [helperPath, "status"]
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
  }

  function requestPreset(name) {
    if (applying) return
    pendingPreset = pendingPreset === name ? "" : name
  }

  function applyPending() {
    if (pendingPreset === "" || applying) return
    applying = true
    errorText = ""
    actionProc.requestedPreset = pendingPreset
    actionProc.command = [helperPath, "preset", pendingPreset]
    actionProc.running = true
  }

  function initializeDevice() {
    if (applying) return
    if (pendingPreset !== "initialize") {
      pendingPreset = "initialize"
      return
    }
    applying = true
    errorText = ""
    actionProc.requestedPreset = "initialize"
    actionProc.command = [helperPath, "initialize"]
    actionProc.running = true
  }

  function presetLabel(name) {
    if (name === "quiet") return "Quiet"
    if (name === "balanced") return "Balanced"
    if (name === "performance") return "Performance"
    if (name === "full") return "Full Speed"
    return "Initialize"
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.errorText = String(text).trim()
    }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0) root.connected = false
    }
  }

  Process {
    id: actionProc
    property string requestedPreset: ""
    property string output: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: actionProc.output = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.errorText = String(text).trim()
    }
    onExited: function(exitCode) {
      root.applying = false
      if (exitCode === 0) {
        root.lastProfile = root.presetLabel(actionProc.requestedPreset)
        root.pendingPreset = ""
        root.errorText = ""
      } else if (root.errorText === "") {
        root.errorText = "Could not apply " + root.presetLabel(actionProc.requestedPreset)
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰈐"
    tooltipText: root.connected
      ? "Corsair cooling · " + (root.waterTemp > 0 ? root.waterTemp.toFixed(1) + "°C" : "temperature unavailable")
        + " · pump " + root.pumpRpm + " RPM"
      : "Corsair cooling · press r or middle-click to refresh"
    foreground: root.opened ? Color.accent : root.temperatureColor

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }

    Text {
      anchors.left: parent.horizontalCenter
      anchors.leftMargin: Style.space(5)
      anchors.verticalCenter: parent.verticalCenter
      text: root.waterTemp > 0 ? Math.round(root.waterTemp) + "°" : "--"
      textFormat: Text.PlainText
      color: root.temperatureColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: Math.min(Style.space(360), panel.availableCardWidth)
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(key) {
        if (key === "r") root.refresh()
      }

      Column {
        id: content
        anchors.fill: parent
        spacing: Style.space(8)

        PanelSectionHeader {
          width: parent.width
          text: "Corsair Commander CORE"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        PanelSeparator { width: parent.width }

        Row {
          width: parent.width
          spacing: Style.space(18)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.space(2)
            Text {
              text: root.waterTemp > 0 ? root.waterTemp.toFixed(1) + "°C" : "—"
              color: root.temperatureColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: "Coolant"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.space(2)
            Text {
              text: root.pumpRpm >= 0 ? root.pumpRpm + " RPM" : "—"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: "AIO pump"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        PanelSectionHeader {
          width: parent.width
          text: "Fans"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Grid {
          width: parent.width
          columns: 3
          rowSpacing: Style.space(5)
          columnSpacing: Style.space(5)

          Repeater {
            model: root.fans
            delegate: Rectangle {
              required property var modelData
              width: (content.width - Style.space(10)) / 3
              height: Style.space(42)
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
              Column {
                anchors.centerIn: parent
                spacing: Style.space(1)
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.rpm + " RPM"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.name
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        PanelSeparator { width: parent.width }

        PanelSectionHeader {
          width: parent.width
          text: "Cooling profile"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          width: parent.width
          text: "Last applied: " + root.lastProfile
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Grid {
          width: parent.width
          columns: 2
          rowSpacing: Style.space(6)
          columnSpacing: Style.space(6)

          Repeater {
            model: ["quiet", "balanced", "performance", "full"]
            delegate: Button {
              required property string modelData
              width: (content.width - Style.space(6)) / 2
              text: root.presetLabel(modelData)
              bordered: root.pendingPreset === modelData
              enabled: !root.applying
              foreground: modelData === "full" ? root.urgent : root.foreground
              fontFamily: root.fontFamily
              onClicked: root.requestPreset(modelData)
            }
          }
        }

        Rectangle {
          width: parent.width
          height: root.pendingPreset !== "" ? confirmColumn.implicitHeight + Style.space(14) : 0
          visible: root.pendingPreset !== ""
          radius: Style.cornerRadius
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)

          Column {
            id: confirmColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(7)
            anchors.rightMargin: Style.space(7)
            spacing: Style.space(5)

            Text {
              width: parent.width
              text: root.pendingPreset === "initialize"
                ? "Initialize controller? Lighting may flash once."
                : "Apply " + root.presetLabel(root.pendingPreset) + " to all six fans and AIO pump?"
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(6)
              Button {
                text: "Cancel"
                enabled: !root.applying
                foreground: root.muted
                fontFamily: root.fontFamily
                onClicked: root.pendingPreset = ""
              }
              Button {
                text: root.applying ? "Applying…" : "Confirm"
                bordered: true
                enabled: !root.applying
                foreground: root.pendingPreset === "full" ? root.urgent : Color.accent
                accent: root.pendingPreset === "full" ? root.urgent : Color.accent
                fontFamily: root.fontFamily
                onClicked: root.pendingPreset === "initialize"
                  ? root.initializeDevice() : root.applyPending()
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.errorText !== ""
          text: root.errorText
          wrapMode: Text.WordWrap
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          width: parent.width
          spacing: Style.space(6)
          Button {
            text: "Initialize controller"
            enabled: !root.applying
            foreground: root.muted
            fontFamily: root.fontFamily
            onClicked: root.initializeDevice()
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "r refreshes (RGB may flash once) · Esc closes"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  IpcHandler {
    target: "matteodevenuto.corsair-cooling"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function status(): string {
      return JSON.stringify({
        connected: root.connected,
        coolantC: root.waterTemp,
        pumpRpm: root.pumpRpm,
        fans: root.fans,
        applying: root.applying,
        error: root.errorText
      })
    }
  }
}
