import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Shapes
import qs.Commons
import qs.Ui

// Tabbed Commander CORE panel styled after meviusisback.hw-monitor:
// Overview (telemetry), Cooling (fan curve + pump) and Lighting (corsair-rgbd).
KeyboardPanel {
  id: root

  required property var widget
  property string tab: "overview"

  readonly property color baseColor: root.bar ? root.bar.foreground : Color.foreground
  readonly property color hotColor: root.bar ? root.bar.urgent : Color.urgent
  readonly property color dimColor: Qt.darker(baseColor, 1.45)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  // ---------------------------------------------------------------- cooling

  readonly property var presets: ({
    "Quiet": { pump: 75, curve: [[28, 30], [32, 35], [35, 45], [38, 60], [41, 75], [43, 90], [45, 100]] },
    "Balanced": { pump: 85, curve: [[26, 35], [30, 40], [34, 55], [37, 70], [40, 85], [43, 100]] },
    "Performance": { pump: 100, curve: [[25, 50], [30, 60], [34, 70], [37, 85], [40, 100]] },
    "Full Speed": { pump: 100, curve: [[20, 100], [60, 100]] }
  })
  property string draftName: "Balanced"
  property int draftPump: 85
  property var draftPoints: presets["Balanced"].curve
  property bool confirmApply: false
  property bool confirmInit: false

  function loadPreset(name) {
    draftName = name
    draftPump = presets[name].pump
    draftPoints = presets[name].curve
    confirmApply = false
  }

  function resetDraft() {
    if (widget.profileCurve && widget.profileCurve.length >= 2) {
      draftName = widget.profileName
      draftPump = widget.profilePump
      draftPoints = widget.profileCurve
      confirmApply = false
    } else {
      loadPreset("Balanced")
    }
  }

  readonly property bool draftIsApplied: JSON.stringify(draftPoints) === JSON.stringify(widget.profileCurve)
    && draftPump === widget.profilePump

  // --------------------------------------------------------------- lighting

  property string editZone: "all"
  property real previewTime: 0
  readonly property var zoneCfg: {
    var l = widget.lighting || {}
    var z = l[editZone === "all" ? "aio" : editZone]
    return z || { effect: "static", color: "theme", brightness: 100, speed: 5 }
  }
  readonly property var themeColors: (widget.lighting && widget.lighting.theme) || ({ accent: "ffffff", palette: [] })
  readonly property bool usesColor: ["static", "breathing", "wave", "spinner"].indexOf(zoneCfg.effect) >= 0
  readonly property bool animated: ["static", "off", "temperature"].indexOf(zoneCfg.effect) < 0
  readonly property var effects: [
    { value: "static", label: "󰝤 Static" },
    { value: "breathing", label: "󰖙 Breathing" },
    { value: "wave", label: "󰖌 Wave" },
    { value: "spinner", label: "󰑮 Spinner" },
    { value: "palette", label: "󰏘 Theme palette" },
    { value: "rainbow", label: "󰃟 Rainbow" },
    { value: "spectrum", label: "󰸌 Color cycle" },
    { value: "temperature", label: "󰔏 Coolant temp" },
    { value: "off", label: "󰛨 Off" }
  ]
  readonly property var swatches: ["theme", "ffffff", "ff0000", "ff6000", "ffc800",
    "00ff40", "00e0ff", "0040ff", "8000ff", "ff0080"]

  function setZone(field, value) {
    var z = { effect: zoneCfg.effect, color: zoneCfg.color, brightness: zoneCfg.brightness, speed: zoneCfg.speed }
    z[field] = value
    widget.setLighting(editZone, z.effect, z.color, z.brightness, z.speed)
  }

  function toHex(c) {
    return [c.r, c.g, c.b].map(function(v) { return ("0" + Math.round(v * 255).toString(16)).slice(-2) }).join("")
  }

  // ----------------------------------------------------------------- shared

  function coolantSeverity(t) { return t >= 43 ? 2 : (t >= 40 ? 1 : 0) }

  readonly property int fanMaxRpm: {
    var m = 2000
    for (var i = 0; i < widget.fans.length; i++) m = Math.max(m, widget.fans[i].rpm)
    return m
  }
  readonly property int fanAvgRpm: {
    if (widget.fans.length === 0) return -1
    var sum = 0, n = 0
    for (var i = 0; i < widget.fans.length; i++) if (widget.fans[i].rpm > 0) { sum += widget.fans[i].rpm; n++ }
    return n ? Math.round(sum / n) : 0
  }

  onOpenChanged: {
    if (open) {
      widget.reloadConfig()
      resetDraft()
    } else {
      confirmApply = false
      confirmInit = false
    }
  }

  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Style.space(480))
  contentHeight: fittedContentHeight(panelColumn.implicitHeight + Style.space(16), Style.space(900))

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: root.close()
    onTabRequested: function(direction) {
      if (root.owner && typeof root.owner.switchPanel === "function") root.owner.switchPanel(direction)
    }
    onTextKey: function(t) {
      if (t === "1") root.tab = "overview"
      else if (t === "2") root.tab = "cooling"
      else if (t === "3") root.tab = "lighting"
      else if (t === "r" || t === "R") widget.refresh()
    }

    Timer {
      interval: 66  // corsair-rgbd renders at 15 fps
      repeat: true
      running: root.open && root.tab === "lighting"
      onTriggered: root.previewTime += interval / 1000
    }

    Controls.ScrollView {
      id: scrollArea
      anchors.fill: parent
      clip: true
      Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
      Controls.ScrollBar.vertical.policy: panelColumn.implicitHeight > scrollArea.height ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff

      Binding {
        target: scrollArea.contentItem
        property: "interactive"
        value: panelColumn.implicitHeight > scrollArea.height
      }

      Column {
        id: panelColumn
        width: scrollArea.availableWidth
        spacing: Style.space(12)

        // Header
        Item {
          width: parent.width
          implicitHeight: Math.max(headerLeft.implicitHeight, refreshChip.implicitHeight)

          Row {
            id: headerLeft
            anchors.left: parent.left
            anchors.right: refreshChip.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              text: "󰈐"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              width: parent.width - Style.font.display - Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: "Cooling"
                color: root.baseColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                text: "Corsair Commander CORE"
                  + (widget.profileName ? " · " + widget.profileName : "")
                color: root.dimColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }

          ModeChip {
            id: refreshChip
            label: widget.loading ? "󰑓 …" : "󰑓"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onPicked: widget.refresh()
          }
        }

        // Tabs
        Row {
          id: tabs
          width: parent.width
          spacing: Style.space(4)
          readonly property var items: [
            { value: "overview", label: "󰕮  Overview" },
            { value: "cooling", label: "󰈐  Cooling" },
            { value: "lighting", label: "󰌵  Lighting" }
          ]

          Repeater {
            model: tabs.items
            delegate: ModeChip {
              required property var modelData
              width: (tabs.width - tabs.spacing * 2) / 3
              label: modelData.label
              selected: root.tab === modelData.value
              onPicked: root.tab = modelData.value
            }
          }
        }

        // ============================================================ Overview
        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: root.tab === "overview"

          Row {
            width: parent.width
            spacing: Style.space(8)

            Dial {
              width: (parent.width - parent.spacing * 2) / 3
              title: "Coolant"
              valueText: widget.waterTemp > 0 ? widget.waterTemp.toFixed(1) + "°" : "–"
              subText: widget.waterTemp > 0 ? (widget.waterTemp < 40 ? "healthy" : (widget.waterTemp < 43 ? "warm" : "hot")) : ""
              ratio: widget.waterTemp > 0 ? (widget.waterTemp - 20) / 30 : 0
              severity: root.coolantSeverity(widget.waterTemp)
              baseColor: root.baseColor
              hotColor: root.hotColor
              accentColor: Color.accent
              fontFamily: root.fontFamily
            }

            Dial {
              width: (parent.width - parent.spacing * 2) / 3
              title: "Pump"
              valueText: widget.pumpRpm >= 0 ? String(widget.pumpRpm) : "–"
              subText: "RPM"
              ratio: widget.pumpRpm > 0 ? widget.pumpRpm / 3000 : 0
              baseColor: root.baseColor
              hotColor: root.hotColor
              accentColor: Color.accent
              fontFamily: root.fontFamily
            }

            Dial {
              width: (parent.width - parent.spacing * 2) / 3
              title: "Fans"
              valueText: root.fanAvgRpm >= 0 ? String(root.fanAvgRpm) : "–"
              subText: "avg RPM"
              ratio: root.fanAvgRpm > 0 ? root.fanAvgRpm / root.fanMaxRpm : 0
              baseColor: root.baseColor
              hotColor: root.hotColor
              accentColor: Color.accent
              fontFamily: root.fontFamily
            }
          }

          Card {
            icon: "󰔏"
            title: "Coolant · last " + Math.max(1, Math.round(widget.coolantHistory.length * 3 / 60)) + " min"
            trailing: {
              var h = widget.coolantHistory
              if (h.length < 2) return "collecting…"
              return Math.min.apply(null, h).toFixed(1) + "° – " + Math.max.apply(null, h).toFixed(1) + "°"
            }

            Item {
              id: spark
              width: parent.width
              height: Style.space(64)
              readonly property var samples: widget.coolantHistory
              readonly property real lo: samples.length ? Math.min.apply(null, samples) - 0.5 : 0
              readonly property real hi: samples.length ? Math.max.apply(null, samples) + 0.5 : 1
              readonly property var line: {
                var out = []
                var n = samples.length
                for (var i = 0; i < n; i++)
                  out.push(Qt.point(i / Math.max(1, n - 1) * width,
                                    height - (samples[i] - lo) / (hi - lo) * height))
                return out
              }

              Repeater {
                model: 3
                delegate: Rectangle {
                  required property int index
                  width: spark.width
                  height: 1
                  y: spark.height * (index + 1) / 4
                  color: Qt.rgba(root.baseColor.r, root.baseColor.g, root.baseColor.b, 0.06)
                }
              }

              Shape {
                anchors.fill: parent
                visible: spark.line.length >= 2
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                  strokeColor: "transparent"
                  fillColor: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.10)
                  PathPolyline {
                    path: spark.line.length < 2 ? [] : spark.line.concat([
                      Qt.point(spark.line[spark.line.length - 1].x, spark.height), Qt.point(0, spark.height)])
                  }
                }
                ShapePath {
                  strokeWidth: 2
                  strokeColor: Color.accent
                  fillColor: "transparent"
                  joinStyle: ShapePath.RoundJoin
                  PathPolyline { path: spark.line }
                }
              }

              Text {
                anchors.centerIn: parent
                visible: spark.line.length < 2
                text: widget.rgbdRunning ? "Collecting samples…" : "Start corsair-rgbd for live history"
                color: root.dimColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Card {
            icon: "󰈐"
            title: "Pump & fans"
            trailing: widget.connected ? "live" : "disconnected"

            Meter {
              label: "AIO pump"
              valueText: widget.pumpRpm >= 0 ? widget.pumpRpm + " RPM" : "–"
              ratio: widget.pumpRpm > 0 ? widget.pumpRpm / 3000 : 0
            }

            Repeater {
              model: widget.fans
              delegate: Meter {
                required property var modelData
                label: modelData.name
                valueText: modelData.rpm > 0 ? modelData.rpm + " RPM" : "not spinning"
                ratio: modelData.rpm / root.fanMaxRpm
              }
            }
          }
        }

        // ============================================================= Cooling
        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: root.tab === "cooling"

          Card {
            icon: "󰈐"
            title: "Fan curve"
            trailing: widget.profileName ? "on controller: " + widget.profileName : "controller curve unknown"

            Flow {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: ["Quiet", "Balanced", "Performance", "Full Speed"]
                delegate: ModeChip {
                  required property string modelData
                  label: modelData
                  selected: root.draftName === modelData
                  activeColor: modelData === "Full Speed" ? root.hotColor : Color.accent
                  onPicked: root.loadPreset(modelData)
                }
              }
              ModeChip {
                label: "󰏫 Custom"
                selected: root.draftName === "Custom"
                onPicked: root.draftName = "Custom"
              }
            }

            CurveEditor {
              id: editor
              width: parent.width
              height: Style.space(200)
              points: root.draftPoints
              reference: widget.profileCurve
              coolant: widget.waterTemp
              baseColor: root.baseColor
              lineColor: Color.accent
              hotColor: root.hotColor
              fontFamily: root.fontFamily
              onEdited: function(pts) {
                root.draftPoints = pts
                root.draftName = "Custom"
                root.confirmApply = false
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Drag points · double-click adds · right-click removes · dashed line is what the controller runs now"
              color: root.dimColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            InfoPair {
              label: "At " + (widget.waterTemp > 0 ? widget.waterTemp.toFixed(1) + "°C" : "current coolant")
              value: widget.waterTemp > 0
                ? "fans " + Math.round(editor.dutyAt(root.draftPoints, widget.waterTemp)) + "% · pump " + root.draftPump + "%"
                : "–"
            }
          }

          Card {
            icon: "󰡲"
            title: "AIO pump"
            trailing: root.draftPump + "%"

            PanelSlider {
              width: parent.width
              bar: root.bar
              minimum: 50
              maximum: 100
              step: 5
              integer: true
              value: root.draftPump
              onMoved: function(v) {
                root.draftPump = Math.round(v)
                if (root.draftName !== "Custom" && root.presets[root.draftName].pump !== root.draftPump) root.draftName = "Custom"
                root.confirmApply = false
              }
            }
          }

          Row {
            anchors.right: parent.right
            spacing: Style.space(6)

            Button {
              text: "Reset"
              visible: !root.draftIsApplied && widget.profileCurve.length > 0
              enabled: !widget.applying
              foreground: root.dimColor
              fontFamily: root.fontFamily
              onClicked: root.resetDraft()
            }
            Button {
              text: "Cancel"
              visible: root.confirmApply
              enabled: !widget.applying
              foreground: root.dimColor
              fontFamily: root.fontFamily
              onClicked: root.confirmApply = false
            }
            Button {
              text: widget.applying ? "Applying…"
                : (root.confirmApply ? "Confirm " + root.draftName : (root.draftIsApplied ? "Applied" : "Apply " + root.draftName))
              bordered: true
              enabled: !widget.applying && !root.draftIsApplied
              foreground: root.draftName === "Full Speed" ? root.hotColor : Color.accent
              accent: root.draftName === "Full Speed" ? root.hotColor : Color.accent
              fontFamily: root.fontFamily
              onClicked: {
                if (!root.confirmApply) { root.confirmApply = true; return }
                root.confirmApply = false
                widget.applyProfile(root.draftName, root.draftPump, root.draftPoints)
              }
            }
          }

          Card {
            icon: "󰒓"
            title: "Controller"

            InfoPair {
              label: "Lighting daemon"
              value: widget.rgbdRunning ? "running" : "stopped"
              valueColor: widget.rgbdRunning ? root.baseColor : root.hotColor
            }

            Row {
              spacing: Style.space(6)
              Button {
                text: root.confirmInit ? "Confirm initialize" : "Initialize controller"
                enabled: !widget.applying
                foreground: root.confirmInit ? Color.accent : root.dimColor
                fontFamily: root.fontFamily
                onClicked: {
                  if (!root.confirmInit) { root.confirmInit = true; return }
                  root.confirmInit = false
                  widget.initializeDevice()
                }
              }
              Button {
                visible: root.confirmInit
                text: "Cancel"
                foreground: root.dimColor
                fontFamily: root.fontFamily
                onClicked: root.confirmInit = false
              }
            }
          }
        }

        // ============================================================ Lighting
        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: root.tab === "lighting"

          Card {
            visible: !widget.rgbdRunning
            icon: "󰌵"
            title: "Lighting needs corsair-rgbd"

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "The daemon keeps the controller in software mode so reads never flash and effects run smoothly. Enable it once:\n\nsystemctl --user link ~/.config/omarchy/plugins/matteodevenuto.corsair-cooling/corsair-rgbd.service\nsystemctl --user enable --now corsair-rgbd"
              color: root.baseColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(12)
            visible: widget.rgbdRunning

            // Zone + live preview
            Card {
              icon: "󰛨"
              title: "Preview"
              trailing: "live"

              Row {
                id: zones
                width: parent.width
                spacing: Style.space(4)
                readonly property var items: [
                  { value: "all", label: "All" },
                  { value: "aio", label: "Pump head" },
                  { value: "fans", label: "Fans" }
                ]
                Repeater {
                  model: zones.items
                  delegate: ModeChip {
                    required property var modelData
                    width: (zones.width - zones.spacing * 2) / 3
                    label: modelData.label
                    selected: root.editZone === modelData.value
                    onPicked: root.editZone = modelData.value
                  }
                }
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(28)

                LedPreview {
                  width: Style.space(110)
                  count: 29
                  dot: Style.space(6)
                  label: "PUMP HEAD"
                  zone: widget.lighting.aio || ({})
                  theme: root.themeColors
                  coolant: widget.waterTemp
                  time: root.previewTime
                  labelColor: root.baseColor
                  fontFamily: root.fontFamily
                  opacity: root.editZone === "fans" ? 0.45 : 1
                  Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                LedPreview {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(80)
                  count: 8
                  dot: Style.space(9)
                  label: "FANS"
                  zone: widget.lighting.fans || ({})
                  theme: root.themeColors
                  coolant: widget.waterTemp
                  time: root.previewTime
                  labelColor: root.baseColor
                  fontFamily: root.fontFamily
                  opacity: root.editZone === "aio" ? 0.45 : 1
                  Behavior on opacity { NumberAnimation { duration: 160 } }
                }
              }
            }

            Card {
              icon: "󰏘"
              title: "Effect"
              trailing: root.editZone === "all" ? "pump head + fans" : (root.editZone === "aio" ? "pump head" : "fans")

              Flow {
                width: parent.width
                spacing: Style.space(4)
                Repeater {
                  model: root.effects
                  delegate: ModeChip {
                    required property var modelData
                    label: modelData.label
                    selected: root.zoneCfg.effect === modelData.value
                    onPicked: root.setZone("effect", modelData.value)
                  }
                }
              }
            }

            Card {
              icon: "󰸌"
              title: "Color"
              trailing: root.usesColor ? (root.zoneCfg.color === "theme" ? "theme accent" : "#" + root.zoneCfg.color) : "set by effect"
              opacity: root.usesColor ? 1 : 0.4
              Behavior on opacity { NumberAnimation { duration: 160 } }

              Flow {
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: root.swatches
                  delegate: Rectangle {
                    required property string modelData
                    readonly property bool picked: root.zoneCfg.color === modelData
                    width: Style.space(26)
                    height: width
                    radius: width / 2
                    color: "#" + (modelData === "theme" ? root.themeColors.accent : modelData)
                    border.width: picked ? Style.space(2) : 1
                    border.color: picked ? root.baseColor : Qt.rgba(root.baseColor.r, root.baseColor.g, root.baseColor.b, 0.2)
                    scale: swatchMouse.pressed ? 0.9 : (swatchMouse.containsMouse ? 1.08 : 1)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    Text {
                      anchors.centerIn: parent
                      visible: modelData === "theme"
                      text: "󰏘"
                      color: Color.background
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      id: swatchMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      enabled: root.usesColor
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setZone("color", modelData)
                    }
                  }
                }
              }

              Text {
                text: "Custom hue"
                color: Qt.darker(root.baseColor, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Rectangle {
                width: parent.width
                height: Style.space(4)
                radius: height / 2
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0.0; color: "#ff0000" }
                  GradientStop { position: 0.17; color: "#ffff00" }
                  GradientStop { position: 0.33; color: "#00ff00" }
                  GradientStop { position: 0.5; color: "#00ffff" }
                  GradientStop { position: 0.67; color: "#0000ff" }
                  GradientStop { position: 0.83; color: "#ff00ff" }
                  GradientStop { position: 1.0; color: "#ff0000" }
                }
              }

              PanelSlider {
                width: parent.width
                bar: root.bar
                enabled: root.usesColor
                minimum: 0
                maximum: 359
                step: 1
                integer: true
                value: {
                  var c = root.zoneCfg.color
                  if (!c || c === "theme") return 0
                  var h = Qt.color("#" + c).hsvHue
                  return h < 0 ? 0 : Math.round(h * 359)
                }
                fillColor: Qt.hsva(liveValue / 360, 1, 1, 1)
                knobColor: Qt.hsva(liveValue / 360, 1, 1, 1)
                onReleased: function(v) { root.setZone("color", root.toHex(Qt.hsva(v / 360, 1, 1, 1))) }
              }
            }

            Card {
              icon: "󰃠"
              title: "Brightness & speed"

              InfoPair { label: "Brightness"; value: root.zoneCfg.brightness + "%" }
              PanelSlider {
                width: parent.width
                bar: root.bar
                minimum: 0
                maximum: 100
                step: 5
                integer: true
                value: root.zoneCfg.brightness
                onReleased: function(v) { root.setZone("brightness", Math.round(v)) }
              }

              InfoPair {
                visible: root.animated
                label: "Speed"
                value: root.zoneCfg.speed + " / 10"
              }
              PanelSlider {
                visible: root.animated
                width: parent.width
                bar: root.bar
                minimum: 1
                maximum: 10
                step: 1
                integer: true
                tickCount: 10
                value: root.zoneCfg.speed
                onReleased: function(v) { root.setZone("speed", Math.round(v)) }
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: widget.errorText !== ""
          textFormat: Text.PlainText
          text: widget.errorText
          wrapMode: Text.WordWrap
          color: root.hotColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignRight
          text: "1 2 3 tabs · r refresh · Esc close"
          color: Qt.darker(root.baseColor, 1.8)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ------------------------------------------------------------- components

  component ModeChip: Rectangle {
    id: chip
    property string label: ""
    property bool selected: false
    property color activeColor: Color.accent
    signal picked()

    implicitWidth: chipLabel.implicitWidth + Style.space(12)
    implicitHeight: chipLabel.implicitHeight + Style.space(8)
    radius: Style.cornerRadius
    color: chip.selected ? activeColor : (chipMouse.containsMouse ? Qt.rgba(root.baseColor.r, root.baseColor.g, root.baseColor.b, 0.12) : Qt.rgba(root.baseColor.r, root.baseColor.g, root.baseColor.b, 0.06))
    border.color: chip.selected ? activeColor : Qt.rgba(root.baseColor.r, root.baseColor.g, root.baseColor.b, 0.12)
    border.width: 1

    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on border.color { ColorAnimation { duration: 140 } }

    scale: chipMouse.pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Text {
      id: chipLabel
      anchors.centerIn: parent
      text: chip.label
      color: chip.selected ? Color.background : root.baseColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: chip.selected
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.picked()
    }
  }

  component Card: Rectangle {
    id: card
    property string icon: ""
    property string title: ""
    property string trailing: ""
    default property alias content: cardBody.data

    width: parent ? parent.width : 0
    implicitHeight: cardCol.implicitHeight + Style.space(24)
    color: Qt.rgba(root.baseColor.r, root.baseColor.g, root.baseColor.b, 0.04)
    border.color: Qt.rgba(root.baseColor.r, root.baseColor.g, root.baseColor.b, 0.10)
    border.width: 1
    radius: Style.cornerRadius

    Column {
      id: cardCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(12)
      spacing: Style.space(10)

      Item {
        width: parent.width
        implicitHeight: cardTitle.implicitHeight

        Row {
          spacing: Style.space(6)
          Text {
            textFormat: Text.PlainText
            text: card.icon
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            id: cardTitle
            textFormat: Text.PlainText
            text: card.title
            color: root.baseColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: card.trailing
          color: root.dimColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Column {
        id: cardBody
        width: parent.width
        spacing: Style.space(8)
      }
    }
  }

  component InfoPair: Item {
    id: pair
    property string label: ""
    property string value: ""
    property color valueColor: root.baseColor

    width: parent ? parent.width : 0
    implicitHeight: Math.max(pairLabel.implicitHeight, pairValue.implicitHeight)

    Text {
      id: pairLabel
      textFormat: Text.PlainText
      text: pair.label
      color: Qt.darker(root.baseColor, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
    Text {
      id: pairValue
      anchors.right: parent.right
      textFormat: Text.PlainText
      text: pair.value
      color: pair.valueColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      Behavior on color { ColorAnimation { duration: 240 } }
    }
  }

  component Meter: Column {
    id: meter
    property string label: ""
    property string valueText: ""
    property real ratio: 0

    width: parent ? parent.width : 0
    spacing: Style.space(4)

    InfoPair { label: meter.label; value: meter.valueText }

    Rectangle {
      width: parent.width
      height: Style.space(4)
      radius: height / 2
      color: Qt.rgba(root.baseColor.r, root.baseColor.g, root.baseColor.b, 0.12)

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        radius: parent.radius
        color: Color.accent
        width: Math.max(meter.ratio > 0 ? parent.height : 0, parent.width * Math.max(0, Math.min(1, meter.ratio)))
        Behavior on width { NumberAnimation { duration: 240 } }
      }
    }
  }
}
