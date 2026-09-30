import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Mouse widget: battery, DPI, polling rate, and a pointer-acceleration switch.
//
// Everything device-side is read by bin/omarchy-mouse-status, which talks the
// Razer HID protocol directly (UPower does not see these mice) and falls back
// to UPower for anything else. The widget only renders what that prints, so a
// different mouse needs no QML changes -- just another branch in the helper.
Panel {
  id: root
  moduleName: "user.mouse"
  ipcTarget: "user.mouse"
  // Owning the IpcHandler outright so `toggleAccel` can join the standard
  // open/close/toggle set -- a target only routes to one handler.
  manageIpc: false

  // Last good status payload. Never cleared on a failed read: a dropped poll
  // should leave the previous numbers on screen, not blank the widget.
  property var info: ({})
  property bool accelBusy: false
  // Keyboard cursor gate: the panel has exactly one control, and Enter must
  // not flip pointer acceleration the instant the popup takes focus. An
  // arrow key arms the cursor first, matching the power panel.
  property bool cursorActive: false

  // Scripts live beside this file, so the plugin keeps working if the whole
  // directory is renamed or moved.
  readonly property string statusBin: Qt.resolvedUrl("bin/omarchy-mouse-status").toString().replace(/^file:\/\//, "")
  readonly property string accelBin: Qt.resolvedUrl("bin/omarchy-mouse-accel").toString().replace(/^file:\/\//, "")

  readonly property bool present: !!(info && info.present === true)
  readonly property bool online: !!(info && info.online === true)
  readonly property var battery: (info && typeof info.battery === "number") ? info.battery : null
  readonly property bool charging: !!(info && info.charging === true)
  // Unknown (helper could not ask Hyprland) is treated as on, matching the
  // libinput default rather than claiming acceleration is off.
  readonly property bool accelOn: info ? info.accel !== false : true
  readonly property bool lowBattery: !!Model.isLow(battery, charging)
  readonly property bool hasStages: !!(info && info.dpiStages && info.dpiStages.length > 0)
  readonly property string deviceName: (info && info.name) ? info.name : "Mouse"

  readonly property bool showPercentage: setting("showPercentage", false) === true
  readonly property int refreshSec: Math.max(15, setting("refreshIntervalSec", 120))

  readonly property color accentForeground: bar ? bar.foreground : Color.foreground

  // A percentage next to the glyph paints a wider block than an icon, so the
  // open-panel mark measures the painted text instead of the icon slot.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function applyStatus(text) {
    var parsed = Model.parseStatus(text)
    if (parsed) root.info = parsed
  }

  function setAccel(enabled) {
    if (accelBusy) return
    accelBusy = true
    // Throw the switch immediately rather than waiting for the round trip;
    // the next poll confirms it (or puts it back if the eval was rejected).
    var next = Object.assign({}, root.info)
    next.accel = enabled
    root.info = next
    accelProc.command = [root.accelBin, enabled ? "on" : "off"]
    accelProc.running = true
  }

  function toggleAccel() {
    setAccel(!root.accelOn)
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function barText() {
    // Always the mouse glyph: this sits next to network, bluetooth and audio,
    // where the icon's job is to say *which device* it is. Battery shape is
    // the power widget's language, and the level is spelled out in the popup
    // (or inline here when showPercentage is on).
    if (!root.showPercentage || button.vertical || root.battery === null) return Model.MOUSE_ICON
    return root.battery + "% " + Model.MOUSE_ICON
  }

  function tooltipText() {
    if (!root.present) return "Mouse"
    if (!root.online) return root.deviceName + " — asleep"
    var parts = [root.deviceName]
    if (root.battery !== null) parts.push(Model.batteryLabel(root.info))
    if (typeof root.info.dpi === "number") parts.push(root.info.dpi + " DPI")
    parts.push(root.accelOn ? "accel on" : "accel off")
    return parts.join(" · ")
  }

  IpcHandler {
    target: "user.mouse"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function toggleAccel(): void { root.toggleAccel() }
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      cursorActive = false
    }
  }

  // The whole widget disappears when no mouse is reachable, the same way the
  // power widget hides itself on a desktop with no battery.
  visible: present
  implicitWidth: present ? button.implicitWidth : 0
  implicitHeight: present ? button.implicitHeight : 0

  Process {
    id: statusProc
    command: [root.statusBin]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: accelProc
    onExited: {
      root.accelBusy = false
      root.refresh()
    }
  }

  // Battery moves slowly, so the idle cadence is lazy; an open panel polls
  // often enough that a DPI change made on the mouse itself shows up while
  // you are looking at it.
  Timer {
    interval: root.opened ? 5000 : root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText()
    active: root.lowBattery
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical && root.battery !== null ? 2 : 1)
    tooltipText: root.tooltipText()
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleAccel()
      else if (b === Qt.MiddleButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.present
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.cursorActive = true }
      onActivateRequested: if (root.cursorActive) root.toggleAccel()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: battery glyph · name/state · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          // Brand logo (logos/<brand>.svg, tinted to the theme) when the mouse's
          // maker is known; the battery glyph otherwise. The SVG is read once
          // and re-emitted as a data URL with the fill injected, so it follows
          // theme changes and the low-battery colour exactly like text does.
          Item {
            id: heroIcon
            readonly property string brand: Model.brandKey(root.info)
            readonly property color tint: root.lowBattery ? (root.bar ? root.bar.urgent : Color.urgent) : root.accentForeground
            readonly property real logoSize: Style.font.display * 1.25
            property string svg: ""
            implicitWidth: brand ? logoSize : glyph.implicitWidth
            implicitHeight: brand ? logoSize : glyph.implicitHeight
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Text {
              id: glyph
              visible: !heroIcon.brand
              text: root.online ? Model.batteryIcon(root.battery, root.charging) : Model.MOUSE_ICON
              color: heroIcon.tint
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.centerIn: parent

              Behavior on color { ColorAnimation { duration: 200 } }
            }

            FileView {
              id: logoFile
              path: heroIcon.brand ? Qt.resolvedUrl("logos/" + heroIcon.brand + ".svg").toString().replace(/^file:\/\//, "") : ""
              watchChanges: false
              onLoaded: heroIcon.svg = text()
            }

            Image {
              id: logo
              visible: !!heroIcon.brand && heroIcon.svg !== ""
              anchors.fill: parent
              fillMode: Image.PreserveAspectFit
              smooth: true
              mipmap: true
              sourceSize.width: Math.round(heroIcon.logoSize * 2)
              sourceSize.height: Math.round(heroIcon.logoSize * 2)
              opacity: root.online ? 1 : 0.45
              source: heroIcon.svg === "" ? "" :
                "data:image/svg+xml;utf8," + encodeURIComponent(heroIcon.svg.replace(/<svg /, "<svg fill=\"" + heroIcon.tint.toString() + "\" "))

              Behavior on opacity { NumberAnimation { duration: 200 } }
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.deviceName
              color: root.accentForeground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: Model.statusLine(root.info).toUpperCase()
              color: Qt.darker(root.accentForeground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            text: Model.batteryLabel(root.info)
            color: root.lowBattery ? (root.bar ? root.bar.urgent : Color.urgent) : root.accentForeground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        // ---------- Battery level ----------
        Item {
          visible: root.battery !== null
          width: parent.width
          implicitHeight: root.battery !== null ? Style.space(8) : 0

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.accentForeground.r, root.accentForeground.g, root.accentForeground.b, 0.12)
          }

          Rectangle {
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.lowBattery ? (root.bar ? root.bar.urgent : Color.urgent) : root.accentForeground
            width: Math.max(barTrack.height, barTrack.width * Model.batteryFraction(root.battery))

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }

            SequentialAnimation on opacity {
              running: root.charging && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Pointer acceleration ----------
        PanelSeparator { foreground: root.accentForeground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POINTER"
            foreground: root.accentForeground
            fontFamily: root.bar.fontFamily
          }

          Toggle {
            width: parent.width
            label: "Acceleration"
            description: Model.accelDescription(root.accelOn)
            checked: root.accelOn
            hasCursor: root.cursorActive
            foreground: root.accentForeground
            fontFamily: root.bar.fontFamily
            onClicked: root.toggleAccel()
          }
        }

        // ---------- Device readout ----------
        PanelSeparator {
          visible: root.online
          foreground: root.accentForeground
        }

        Column {
          visible: root.online
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "DEVICE"
            foreground: root.accentForeground
            fontFamily: root.bar.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair { label: "DPI"; value: Model.dpiLabel(root.info) }
            InfoPair { label: "Polling rate"; value: Model.pollingLabel(root.info) }
            InfoPair { label: "Firmware"; value: Model.firmwareLabel(root.info) }
          }

          // On-device DPI stages, with the active one filled in. Read-only:
          // the stage is cycled with the button on the mouse itself.
          Column {
            visible: root.hasStages
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: Model.stageLabel(root.info)
              color: Qt.darker(root.accentForeground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: (root.info && root.info.dpiStages) ? root.info.dpiStages : []

                Rectangle {
                  required property var modelData
                  required property int index

                  // dpiStage is 1-based on the wire, the repeater index is not.
                  readonly property bool current: !!(root.info && root.info.dpiStage === index + 1)

                  implicitWidth: stageLabel.implicitWidth + Style.space(14)
                  implicitHeight: stageLabel.implicitHeight + Style.space(8)
                  radius: Style.cornerRadius > 0 ? height / 2 : 0
                  color: current
                    ? Style.selectedFillFor(root.accentForeground, Color.accent)
                    : Style.normalFillFor(root.accentForeground, Color.accent)

                  Text {
                    id: stageLabel
                    anchors.centerIn: parent
                    text: modelData
                    color: root.accentForeground
                    opacity: parent.current ? 1.0 : 0.55
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: parent.current
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.accentForeground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.accentForeground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
