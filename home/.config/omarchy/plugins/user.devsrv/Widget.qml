import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// user.devsrv bar widget: a server glyph (with the running count) and a panel
// listing running local instances and the ones that ran before. All state
// comes from the engine service (Engine.qml); this file only renders it and
// one instance exists per monitor.
Panel {
  id: root
  moduleName: "user.devsrv"
  ipcTarget: ""
  manageIpc: false

  // The engine registers itself in DevsrvRegistry (see DevsrvRegistry.qml); the bar.shell
  // lookup only works under the trusted first-party bar.
  readonly property var engine: DevsrvRegistry.engine
    || (bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor("user.devsrv") : null)
  readonly property bool showDots: setting("showDotsInBar", true) !== false

  readonly property color accentForeground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color goodColor: Color.accent
  readonly property color badColor: Color.urgent
  readonly property color dimColor: Qt.darker(accentForeground, 1.4)

  readonly property var running: engine ? engine.running : []
  readonly property var recent: engine ? engine.recent : []
  readonly property int runningCount: running.length
  readonly property var rows: Model.buildRows(running, recent)

  // Keyboard cursor over `rows`; headers are skipped when moving.
  property int cursor: -1
  readonly property bool cursorActive: cursor >= 0

  // Wall clock for uptime / "x min ago", ticking only while open.
  property real nowMs: Date.now()
  Timer { interval: 1000; running: root.opened; repeat: true; onTriggered: root.nowMs = Date.now() }

  onSettingsChanged: pushSettings()
  onEngineChanged: pushSettings()
  function pushSettings() {
    if (engine && typeof engine.applySettings === "function") engine.applySettings(settings)
  }

  onOpenedChanged: {
    if (!engine) return
    engine.openPanels = Math.max(0, engine.openPanels + (opened ? 1 : -1))
    if (opened) { cursor = -1; engine.rescan() }
    else keyCatcher.forceActiveFocus()
  }
  Component.onDestruction: if (opened && engine) engine.openPanels = Math.max(0, engine.openPanels - 1)

  function moveCursor(dy) {
    if (!rows.length) return
    var i = cursor < 0 ? (dy > 0 ? -1 : rows.length) : cursor
    for (var n = 0; n < rows.length; n++) {
      i += dy > 0 ? 1 : -1
      if (i < 0 || i >= rows.length) { i = Math.max(0, Math.min(rows.length - 1, i)); if (!Model.isInstance(rows[i])) continue; break }
      if (Model.isInstance(rows[i])) break
    }
    if (Model.isInstance(rows[i])) cursor = i
  }

  function rowAt(index) { return index >= 0 && index < rows.length && Model.isInstance(rows[index]) ? rows[index] : null }
  function busyState(id) { return engine && engine.busy && engine.busy[id] ? engine.busy[id] : "" }

  // Enter: a running instance opens in the browser, a previous one starts.
  function activateRow(index) {
    var row = rowAt(index)
    if (!row || !engine) return
    if (row.type === "running") { if (Model.firstPort(row.inst)) engine.openUrl(row.inst.id, Model.firstPort(row.inst)) }
    else engine.start(row.inst.id)
  }
  function startRow(index) { var r = rowAt(index); if (r && engine && r.type === "recent") engine.start(r.inst.id) }
  function stopRow(index) { var r = rowAt(index); if (r && engine && r.type === "running") engine.stop(r.inst.id) }
  function restartRow(index) { var r = rowAt(index); if (r && engine && r.type === "running") engine.restart(r.inst.id) }
  function folderRow(index) { var r = rowAt(index); if (r && engine) engine.openFolder(r.inst.id) }
  function terminalRow(index) { var r = rowAt(index); if (r && engine) engine.openTerminal(r.inst.id) }
  function logsRow(index) { var r = rowAt(index); if (r && engine && r.inst.log) engine.openLogs(r.inst.id) }
  function forgetRow(index) {
    var r = rowAt(index)
    if (!r || !engine || r.type !== "recent") return
    engine.forget(r.inst.id)
    if (cursor >= rows.length - 1) cursor = -1
  }

  function tooltipText() {
    if (!engine) return "Dev servers"
    if (!runningCount) return "Dev servers — none running"
    var lines = []
    for (var i = 0; i < Math.min(6, running.length); i++) {
      var r = running[i]
      lines.push(r.name + "  " + Model.portsText(r))
    }
    if (running.length > 6) lines.push("… +" + (running.length - 6))
    return lines.join("\n")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.SERVER_ICON
    foreground: root.runningCount > 0 ? root.goodColor : (root.bar ? root.bar.barForeground : Color.foreground)
    active: !!(root.engine && root.engine.lastError)
    tooltipText: root.tooltipText()
    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.engine) root.engine.rescan() }
      else root.toggle()
    }

    // One dot per running instance, hugging the slot edge below the glyph
    // (beside it on a vertical bar). The slot keeps the stock icon width so
    // the button lines up with its neighbours; the dots live in the margin.
    readonly property int maxDots: 6
    readonly property int dotCount: root.showDots ? Math.min(root.runningCount, maxDots) : 0
    readonly property real dotSize: Math.max(2, Style.spaceReal(2.5))
    readonly property real dotGap: Math.max(1, Style.spaceReal(1.5))

    Row {
      visible: button.dotCount > 0 && !button.vertical
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.max(1, Style.spaceReal(2))
      spacing: button.dotGap
      Repeater {
        model: button.dotCount
        Rectangle {
          width: button.dotSize; height: button.dotSize; radius: width / 2
          color: root.goodColor
        }
      }
    }
    Column {
      visible: button.dotCount > 0 && button.vertical
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Math.max(1, Style.spaceReal(2))
      spacing: button.dotGap
      Repeater {
        model: button.dotCount
        Rectangle {
          width: button.dotSize; height: button.dotSize; radius: width / 2
          color: root.goodColor
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    readonly property real maxCardHeight: Math.min(panel.availableCardHeight, panel.screenH * 0.9)
    contentHeight: panel.fittedContentHeight(column.implicitHeight, maxCardHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onReturnRequested: root.activateRow(root.cursor)
      onActivateRequested: root.activateRow(root.cursor)
      onCloseRequested: root.close()
      onDeleteRequested: root.forgetRow(root.cursor)
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r") { if (root.engine) root.engine.rescan() }
        else if (t === "s") root.stopRow(root.cursor)
        else if (t === "R") root.restartRow(root.cursor)
        else if (t === "a" || t === "p") root.startRow(root.cursor)
        else if (t === "o" || t === "f") root.folderRow(root.cursor)
        else if (t === "t") root.terminalRow(root.cursor)
        else if (t === "l") root.logsRow(root.cursor)
        else if (t === "x") root.forgetRow(root.cursor)
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(8)

        // ---------- Title row ----------
        Item {
          id: titleRow
          width: parent.width
          implicitHeight: Math.max(titleText.implicitHeight, titleActions.implicitHeight)

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Model.SERVER_ICON + "  Local instances"
            color: root.accentForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            anchors.left: titleText.right
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.engine && root.engine.scanning ? "scanning…" : (root.runningCount + " running · " + root.recent.length + " remembered")
            color: root.dimColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Row {
            id: titleActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            PanelActionButton {
              iconText: Model.RESTART_ICON
              tooltipText: "Rescan now (r)"
              foreground: root.accentForeground
              fontFamily: root.fontFamily
              onClicked: if (root.engine) root.engine.rescan()
            }
          }
        }

        // ---------- Error line ----------
        Rectangle {
          visible: !!(root.engine && root.engine.lastError)
          width: parent.width
          implicitHeight: visible ? errText.implicitHeight + Style.space(10) : 0
          radius: Math.max(3, Style.cornerRadius / 2)
          color: Qt.rgba(root.badColor.r, root.badColor.g, root.badColor.b, 0.12)
          Text {
            id: errText
            anchors.left: parent.left
            anchors.right: dismiss.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            text: Model.ALERT_ICON + "  " + (root.engine ? root.engine.lastError : "")
            color: root.badColor
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          PanelActionButton {
            id: dismiss
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: Model.REMOVE_ICON
            tooltipText: "Dismiss"
            foreground: root.badColor
            fontFamily: root.fontFamily
            onClicked: if (root.engine) root.engine.clearError()
          }
        }

        // ---------- Rows ----------
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
          height: Math.min(contentHeight, Math.max(Style.space(120), budget))
          clip: true
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          model: root.rows
          currentIndex: root.cursor
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Item {
            id: delegateItem
            required property int index
            required property var modelData
            readonly property bool isHeader: modelData.type === "header"
            readonly property bool isEmpty: modelData.type === "empty"
            readonly property bool isRunning: modelData.type === "running"
            readonly property bool isRecent: modelData.type === "recent"
            readonly property var inst: modelData.inst || ({})
            readonly property string busy: (isRunning || isRecent) ? root.busyState(inst.id) : ""
            readonly property bool missing: (isRunning || isRecent) && inst.exists === false
            readonly property bool docker: Model.isDocker(inst)
            readonly property bool hasFolder: !!inst.cwd && !missing
            width: ListView.view.width
            height: isHeader ? header.implicitHeight : isEmpty ? emptyText.implicitHeight + Style.space(8) : rowSurface.implicitHeight

            // Section header
            Item {
              id: header
              visible: delegateItem.isHeader
              width: parent.width
              implicitHeight: headerText.implicitHeight + Style.space(delegateItem.index === 0 ? 6 : 14)
              Text {
                id: headerText
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(2)
                text: (delegateItem.isHeader ? modelData.title : "") + (delegateItem.isHeader && modelData.count ? "  " + modelData.count : "")
                color: root.dimColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
              }
              PanelSeparator {
                anchors.left: headerText.right
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.verticalCenter: headerText.verticalCenter
                foreground: root.accentForeground
              }
            }

            Text {
              id: emptyText
              visible: delegateItem.isEmpty
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(6)
              text: delegateItem.isEmpty ? modelData.text : ""
              color: root.dimColor
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.italic: true
            }

            // Instance row
            CursorSurface {
              id: rowSurface
              visible: delegateItem.isRunning || delegateItem.isRecent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              hasCursor: root.cursorActive && root.cursor === delegateItem.index
              foreground: root.accentForeground
              implicitHeight: visible ? rowContent.implicitHeight + Style.space(10) : 0

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onEntered: root.cursor = delegateItem.index
                onDoubleClicked: root.activateRow(delegateItem.index)
                onClicked: root.cursor = delegateItem.index
              }

              Item {
                id: rowContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(4)
                implicitHeight: Math.max(labels.implicitHeight, actions.implicitHeight)

                // Status dot: green while up, dim when stopped, pulsing while busy.
                Text {
                  id: dot
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: delegateItem.missing ? Model.ALERT_ICON : Model.DOT_ICON
                  color: delegateItem.busy ? root.accentForeground : delegateItem.isRunning ? root.goodColor : delegateItem.missing ? root.badColor : root.dimColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  SequentialAnimation on opacity {
                    running: !!delegateItem.busy
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.25; duration: 500 }
                    NumberAnimation { from: 0.25; to: 1; duration: 500 }
                    onRunningChanged: if (!running) dot.opacity = 1
                  }
                }

                Column {
                  id: labels
                  anchors.left: dot.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: meta.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: (delegateItem.docker ? Model.DOCKER_ICON + "  " : "") + (delegateItem.inst.name || "")
                    color: root.accentForeground
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: delegateItem.isRunning
                  }
                  Text {
                    width: parent.width
                    text: delegateItem.inst.cmd || ""
                    color: root.accentForeground
                    opacity: 0.8
                    elide: Text.ElideMiddle
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    width: parent.width
                    text: (delegateItem.inst.cwdShort || Model.dockerDetail(delegateItem.inst)) + (delegateItem.missing ? "   (folder missing)" : "")
                    color: delegateItem.missing ? root.badColor : root.dimColor
                    elide: Text.ElideMiddle
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                // Ports + uptime / last seen
                Column {
                  id: meta
                  anchors.right: actions.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)
                  Text {
                    anchors.right: parent.right
                    text: delegateItem.busy ? delegateItem.busy + "…" : Model.portsText(delegateItem.inst)
                    color: delegateItem.isRunning ? root.goodColor : root.dimColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    visible: text !== ""
                  }
                  Text {
                    anchors.right: parent.right
                    text: delegateItem.isRunning ? Model.uptime(delegateItem.inst.since, root.nowMs)
                      : (delegateItem.inst.lastSeen ? Model.CLOCK_ICON + " " + Model.ago(delegateItem.inst.lastSeen, root.nowMs) : "")
                    color: root.dimColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    visible: text !== ""
                  }
                }

                Row {
                  id: actions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  PanelActionButton {
                    visible: delegateItem.isRunning
                    iconText: Model.WEB_ICON
                    tooltipText: Model.firstPort(delegateItem.inst) ? "Open http://localhost:" + Model.firstPort(delegateItem.inst) + " (Enter)" : "No listening port yet"
                    enabled: Model.firstPort(delegateItem.inst) > 0
                    foreground: root.accentForeground
                    fontFamily: root.fontFamily
                    onClicked: root.engine.openUrl(delegateItem.inst.id, Model.firstPort(delegateItem.inst))
                  }
                  PanelActionButton {
                    visible: delegateItem.isRecent
                    iconText: Model.PLAY_ICON
                    tooltipText: "Run again (Enter)\n" + (delegateItem.inst.cmd || "")
                    enabled: !delegateItem.busy && !delegateItem.missing
                    foreground: root.accentForeground
                    hoverColor: root.goodColor
                    fontFamily: root.fontFamily
                    onClicked: root.engine.start(delegateItem.inst.id)
                  }
                  PanelActionButton {
                    iconText: Model.FOLDER_ICON
                    tooltipText: delegateItem.hasFolder ? "Open project folder (o)\n" + delegateItem.inst.cwd : "No project folder for a standalone container"
                    enabled: delegateItem.hasFolder
                    foreground: root.accentForeground
                    fontFamily: root.fontFamily
                    onClicked: root.engine.openFolder(delegateItem.inst.id)
                  }
                  PanelActionButton {
                    iconText: Model.TERMINAL_ICON
                    tooltipText: "Open a terminal in the project folder (t)"
                    enabled: delegateItem.hasFolder
                    foreground: root.accentForeground
                    fontFamily: root.fontFamily
                    onClicked: root.engine.openTerminal(delegateItem.inst.id)
                  }
                  PanelActionButton {
                    iconText: Model.LOG_ICON
                    tooltipText: delegateItem.docker ? "Follow docker logs (l)" : (delegateItem.inst.log ? "Follow the log (l)" : "No log — only instances started here are logged")
                    enabled: !!delegateItem.inst.log
                    foreground: root.accentForeground
                    fontFamily: root.fontFamily
                    onClicked: root.engine.openLogs(delegateItem.inst.id)
                  }
                  PanelActionButton {
                    visible: delegateItem.isRunning
                    iconText: Model.RESTART_ICON
                    tooltipText: delegateItem.docker ? "Restart (R) — down, then up -d" : (delegateItem.inst.unit ? "Restart (R)" : "Restart (R) — re-runs it as a managed unit")
                    enabled: !delegateItem.busy
                    foreground: root.accentForeground
                    fontFamily: root.fontFamily
                    onClicked: root.engine.restart(delegateItem.inst.id)
                  }
                  PanelActionButton {
                    visible: delegateItem.isRunning
                    iconText: Model.STOP_ICON
                    tooltipText: delegateItem.inst.kind === "compose" ? "Stop (s) — docker compose down" : "Stop (s)"
                    enabled: !delegateItem.busy
                    foreground: root.accentForeground
                    hoverColor: root.badColor
                    fontFamily: root.fontFamily
                    onClicked: root.engine.stop(delegateItem.inst.id)
                  }
                  PanelActionButton {
                    visible: delegateItem.isRecent
                    iconText: Model.REMOVE_ICON
                    tooltipText: "Forget this instance (x)"
                    enabled: !delegateItem.busy
                    foreground: root.accentForeground
                    hoverColor: root.badColor
                    fontFamily: root.fontFamily
                    onClicked: root.engine.forget(delegateItem.inst.id)
                  }
                }
              }
            }
          }
        }

        // ---------- Key hints ----------
        Text {
          width: parent.width
          text: "↑↓ move · Enter open / run · s stop · R restart · o folder · t terminal · l log · x forget · r rescan · Esc close"
          color: root.dimColor
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
