import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "../../user.gpu/Model.js" as Model
import "../../user.gpu" as Gpu

// GPU driver indicator for the hover-revealed indicator block. Hidden like
// the other inactive indicators until hovered; becomes "active" (always
// shown, in the active block by the clock) while a driver update is pending,
// a reboot is needed, or an update is running. A theme-accent dot under the
// glyph marks a pending update (urgent colour for reboot needed).
//
// State comes from the user.gpu service (Engine.qml); this file renders it
// and owns the panel, mirroring what Ui/Panel.qml does for bar widgets.
BarIndicator {
  id: root

  readonly property var shell: bar && bar.shell ? bar.shell : null
  // Gpu.GpuRegistry is filled by user.gpu/Engine.qml; the shell lookup only
  // works under the trusted first-party bar (see user.gpu/GpuRegistry.qml).
  readonly property var engine: Gpu.GpuRegistry.engine
    || (shell && typeof shell.serviceFor === "function" ? shell.serviceFor("user.gpu") : null)

  readonly property color accentForeground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color goodColor: Color.accent
  readonly property color badColor: Color.urgent
  readonly property color dimColor: Qt.darker(accentForeground, 1.4)

  readonly property var report: engine ? engine.report : null
  readonly property string state: Model.state(engine)
  readonly property var updates: report && report.updates ? report.updates : []
  readonly property var gpu: report && report.gpus && report.gpus.length ? report.gpus[0] : null
  readonly property var installedRows: Model.installedRows(report, updates)
  readonly property var nvUp: report && report.upstream && report.upstream.nvidia ? report.upstream.nvidia : null
  readonly property bool updating: !!(engine && engine.updating)
  readonly property bool needsAttention: state === "updates" || state === "reboot"

  // ---- indicator contract ----
  active: needsAttention || updating
  activeText: Model.GPU_ICON
  inactiveText: Model.GPU_ICON
  activeTooltipText: tooltipText()
  inactiveTooltipText: tooltipText()
  activeColor: state === "reboot" ? badColor : goodColor
  useActiveColor: needsAttention

  onSettingsChanged: pushSettings()
  onEngineChanged: pushSettings()
  function pushSettings() {
    if (engine && typeof engine.applySettings === "function") engine.applySettings(settings || {})
  }

  onPressed: function(b) {
    if (b === Qt.RightButton) { if (engine) engine.check() }
    else toggle()
  }

  // ---- panel lifecycle (what Ui/Panel.qml provides for bar widgets) ----
  PanelController { id: panelController }
  readonly property alias controller: panelController
  readonly property bool opened: panelController.open
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false
  function open() { panelController.show() }
  function close() { panelController.hide() }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() { popoutSwitchClosing = true; close(); Qt.callLater(function() { popoutSwitchClosing = false }) }
  function switchPanel(direction) { close(); return false }

  property real nowMs: Date.now()
  Timer { interval: 30000; running: root.opened; repeat: true; onTriggered: root.nowMs = Date.now() }
  onOpenedChanged: {
    if (opened) { root.nowMs = Date.now(); if (engine && !engine.report && !engine.checking) engine.check() }
    else keyCatcher.forceActiveFocus()
  }

  function tooltipText() {
    if (!engine) return "GPU drivers"
    var t = Model.headline(engine)
    if (updating) t = "Updating…"
    if (gpu) t = gpu.name + " · " + Model.driverLabel(gpu, report) + "\n" + t
    for (var i = 0; i < Math.min(4, updates.length); i++) t += "\n" + updates[i].name + "  " + updates[i].old + " → " + updates[i].new
    if (report && report.rebootReasons && report.rebootReasons.length) t += "\n" + report.rebootReasons.join("\n")
    return t
  }

  // ---- notification dot ----
  Rectangle {
    id: dot
    visible: root.needsAttention || root.updating
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Math.max(1, Style.spaceReal(2))
    width: Math.max(2, Style.spaceReal(2.5)); height: width; radius: width / 2
    color: root.state === "reboot" ? root.badColor : root.goodColor
    SequentialAnimation on opacity {
      running: root.updating
      loops: Animation.Infinite
      NumberAnimation { from: 1; to: 0.25; duration: 600 }
      NumberAnimation { from: 0.25; to: 1; duration: 600 }
      onRunningChanged: if (!running) dot.opacity = 1
    }
  }

  // ---- panel ----
  KeyboardPanel {
    id: panel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    readonly property real maxCardHeight: Math.min(panel.availableCardHeight, panel.screenH * 0.85)
    contentHeight: panel.fittedContentHeight(column.implicitHeight, maxCardHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onReturnRequested: if (root.engine && root.state === "updates") root.engine.update()
      onActivateRequested: if (root.engine && root.state === "updates") root.engine.update()
      onTextKey: function(t) {
        if (!root.engine) return
        if (t === "r") root.engine.check()
        else if (t === "u") root.engine.update()
        else if (t === "n") root.engine.openReleaseNotes()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)
          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Model.GPU_ICON
            color: root.state === "reboot" || root.state === "error" ? root.badColor : root.state === "updates" ? root.goodColor : root.accentForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }
          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.right: heroActions.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              width: parent.width
              text: root.gpu ? root.gpu.name : "No GPU detected"
              color: root.accentForeground
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              width: parent.width
              text: root.gpu ? Model.driverLabel(root.gpu, root.report) : ""
              color: root.dimColor
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              visible: text !== ""
            }
            Text {
              width: parent.width
              text: root.updating ? Model.UPDATE_ICON + "  Updating… (re-checks when done)"
                : (root.state === "ok" ? Model.CHECK_ICON + "  " : (root.state === "reboot" || root.state === "error") ? Model.ALERT_ICON + "  " : "") + Model.headline(root.engine)
              color: root.state === "reboot" || root.state === "error" ? root.badColor : (root.state === "updates" || root.updating) ? root.goodColor : root.accentForeground
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.state !== "ok"
            }
          }
          Row {
            id: heroActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            PanelActionButton {
              iconText: Model.REFRESH_ICON
              tooltipText: "Check now (r)"
              foreground: root.accentForeground
              fontFamily: root.fontFamily
              enabled: !(root.engine && root.engine.checking)
              onClicked: if (root.engine) root.engine.check()
            }
            PanelActionButton {
              iconText: Model.WEB_ICON
              tooltipText: "Release notes (n)"
              foreground: root.accentForeground
              fontFamily: root.fontFamily
              onClicked: if (root.engine) root.engine.openReleaseNotes()
            }
          }
        }

        // ---------- Reboot reasons / errors ----------
        Rectangle {
          visible: !!(root.report && root.report.rebootReasons && root.report.rebootReasons.length) || !!(root.engine && root.engine.lastError)
          width: parent.width
          implicitHeight: visible ? noteText.implicitHeight + Style.space(10) : 0
          radius: Math.max(3, Style.cornerRadius / 2)
          color: Qt.rgba(root.badColor.r, root.badColor.g, root.badColor.b, 0.12)
          Text {
            id: noteText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(8)
            text: {
              var lines = []
              if (root.report && root.report.rebootReasons) for (var i = 0; i < root.report.rebootReasons.length; i++) lines.push(Model.ALERT_ICON + "  " + root.report.rebootReasons[i])
              if (root.engine && root.engine.lastError) lines.push(Model.ALERT_ICON + "  " + root.engine.lastError)
              return lines.join("\n")
            }
            color: root.badColor
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- Pending updates ----------
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.updates.length > 0
          Text {
            text: "PENDING  " + root.updates.length
            color: root.dimColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
          }
          Repeater {
            model: root.updates
            delegate: Item {
              required property var modelData
              width: parent.width
              implicitHeight: upName.implicitHeight + Style.space(6)
              Text {
                id: upName
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name + (modelData.source === "aur" ? "  (AUR)" : "") + (modelData.reboot ? "  " + Model.RESTART_ICON : "")
                color: root.accentForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.old + "  " + Model.ARROW_ICON + "  " + modelData.new
                color: root.goodColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
          Text {
            width: parent.width
            text: Model.RESTART_ICON + " = a reboot will be needed afterwards. Drivers are updated with the whole system (partial upgrades break Arch)."
            color: root.dimColor
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- Update / reboot buttons ----------
        Row {
          spacing: Style.space(8)
          visible: root.state === "updates" || root.state === "reboot"
          Button {
            visible: root.state === "updates" || (root.report && root.report.totalUpdates > 0)
            text: root.report && root.report.totalUpdates > root.updates.length
              ? "Update system (" + root.report.totalUpdates + " packages)" : "Update now"
            iconText: Model.UPDATE_ICON
            tooltipText: "Runs omarchy update in a floating terminal (u)"
            foreground: root.accentForeground
            accent: root.goodColor
            bordered: true
            enabled: !root.updating
            fontFamily: root.fontFamily
            onClicked: if (root.engine) root.engine.update()
          }
          Button {
            visible: root.state === "reboot"
            text: "Reboot"
            iconText: Model.RESTART_ICON
            tooltipText: "Reboot so the installed driver/kernel gets loaded"
            foreground: root.badColor
            accent: root.badColor
            bordered: true
            fontFamily: root.fontFamily
            onClicked: if (root.engine) root.engine.reboot()
          }
        }

        PanelSeparator { foreground: root.accentForeground }

        Text {
          text: "INSTALLED"
          color: root.dimColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1
        }
        ListView {
          id: list
          width: parent.width
          readonly property real siblingsHeight: {
            var total = 0
            var items = column.children
            for (var i = 0; i < items.length; i++) {
              if (items[i] === list || !items[i].visible) continue
              total += items[i].implicitHeight + column.spacing
            }
            return total
          }
          readonly property real budget: panel.maxCardHeight - panel.verticalContentInset - siblingsHeight
          height: Math.min(contentHeight, Math.max(Style.space(80), budget))
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          model: root.installedRows
          delegate: Item {
            required property var modelData
            width: ListView.view.width
            implicitHeight: pkgName.implicitHeight + Style.space(5)
            height: implicitHeight
            Text {
              id: pkgName
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name
              color: modelData.update ? root.goodColor : root.accentForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.update ? modelData.version + "  " + Model.ARROW_ICON + "  " + modelData.update.new : modelData.version
              color: modelData.update ? root.goodColor : root.dimColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Text {
          width: parent.width
          text: {
            var parts = []
            if (root.nvUp && root.nvUp.latest) parts.push("nvidia.com production branch: " + root.nvUp.latest + (root.nvUp.newer ? "  (newer than installed)" : ""))
            if (root.report && root.report.running && root.report.running.kernel) parts.push("kernel " + root.report.running.kernel)
            parts.push("checked " + Model.ago(root.engine ? root.engine.checkedAt : "", root.nowMs) + " · r check · u update · n notes · Esc")
            return parts.join("\n")
          }
          color: root.dimColor
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
