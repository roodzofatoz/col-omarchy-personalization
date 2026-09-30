import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// user.torrent bar widget: a download glyph (speed beside it while anything
// downloads) and a panel that adds torrents, lists them with progress, and
// streams media files out of them. All state comes from the engine service
// (Engine.qml); this file only renders it and one instance exists per monitor.
Panel {
  id: root
  moduleName: "user.torrent"
  ipcTarget: ""
  manageIpc: false

  // The engine registers itself in TorrentRegistry (see TorrentRegistry.qml); the
  // bar.shell lookup only works under the trusted first-party bar.
  readonly property var engine: TorrentRegistry.engine
    || (bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor("user.torrent") : null)
  readonly property bool showSpeed: setting("showSpeedInBar", true) !== false

  readonly property color accentForeground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color goodColor: Color.accent
  readonly property color badColor: Color.urgent
  readonly property color dimColor: Qt.darker(accentForeground, 1.4)

  readonly property var torrents: engine ? engine.torrents : []
  readonly property string daemonState: engine ? engine.daemon : "unknown"
  readonly property int activeCount: engine ? engine.activeCount : 0
  readonly property int rateDown: engine ? engine.rateDown : 0
  readonly property int rateUp: engine ? engine.rateUp : 0

  // Torrent id -> true while its file list is unfolded.
  property var expanded: ({})
  readonly property var rows: Model.buildRows(torrents, expanded, daemonState)

  // Keyboard cursor over `rows`.
  property int cursor: -1
  readonly property bool cursorActive: cursor >= 0

  // Two-step "delete with data": first press arms this id, second press deletes.
  property int confirmDeleteId: -1
  Timer { id: confirmTimer; interval: 4000; onTriggered: root.confirmDeleteId = -1 }

  onSettingsChanged: pushSettings()
  onEngineChanged: pushSettings()
  function pushSettings() {
    if (engine && typeof engine.applySettings === "function") engine.applySettings(settings)
  }

  onOpenedChanged: {
    if (!engine) return
    engine.openPanels = Math.max(0, engine.openPanels + (opened ? 1 : -1))
    if (opened) { cursor = -1; confirmDeleteId = -1; engine.rescan(false); engine.checkClipboard() }
    else keyCatcher.forceActiveFocus()
  }
  Component.onDestruction: if (opened && engine) engine.openPanels = Math.max(0, engine.openPanels - 1)

  function moveCursor(dy) {
    if (!rows.length) return
    var i = cursor < 0 ? (dy > 0 ? -1 : rows.length) : cursor
    for (var n = 0; n < rows.length; n++) {
      i += dy > 0 ? 1 : -1
      if (i < 0 || i >= rows.length) { i = Math.max(0, Math.min(rows.length - 1, i)); if (!Model.isSelectable(rows[i])) continue; break }
      if (Model.isSelectable(rows[i])) break
    }
    if (Model.isSelectable(rows[i])) cursor = i
  }

  function rowAt(index) { return index >= 0 && index < rows.length && Model.isSelectable(rows[index]) ? rows[index] : null }
  function busyState(id) { return engine && engine.busy && engine.busy[String(id)] ? engine.busy[String(id)] : "" }

  function toggleExpanded(id) {
    var next = Object.assign({}, expanded)
    if (next[String(id)]) delete next[String(id)]; else next[String(id)] = true
    expanded = next
  }

  // Enter / Space: play the row (torrent → its main media file, file → itself).
  function activateRow(index) {
    var row = rowAt(index)
    if (!row || !engine) return
    if (row.type === "file") { if (row.f.media) engine.stream(row.t.id, row.f.index) }
    else if (row.t.bestMedia >= 0) engine.stream(row.t.id, row.t.bestMedia)
    else toggleExpanded(row.t.id)
  }
  function pauseRow(index) { var r = rowAt(index); if (r && engine) engine.toggle(r.t.id) }
  function folderRow(index) { var r = rowAt(index); if (r && engine) engine.openFolder(r.t.id) }
  function filesRow(index) { var r = rowAt(index); if (r) toggleExpanded(r.t.id) }
  function sequentialRow(index) { var r = rowAt(index); if (r && engine) engine.setSequential(r.t.id, !r.t.sequential) }
  function wantedRow(index) { var r = rowAt(index); if (r && engine && r.type === "file") engine.setWanted(r.t.id, r.f.index, !r.f.wanted) }
  function removeRow(index) {
    var r = rowAt(index)
    if (!r || !engine) return
    engine.remove(r.t.id, false)
    if (cursor >= rows.length - 1) cursor = -1
  }
  function deleteRow(index) {
    var r = rowAt(index)
    if (!r || !engine) return
    if (confirmDeleteId === r.t.id) { confirmDeleteId = -1; engine.remove(r.t.id, true); if (cursor >= rows.length - 1) cursor = -1 }
    else { confirmDeleteId = r.t.id; confirmTimer.restart() }
  }

  function enterAdd() { addField.forceActiveFocus(); addField.selectAll() }
  function leaveAdd(toList) {
    keyCatcher.forceActiveFocus()
    if (toList && rows.length && cursor < 0) moveCursor(1)
  }
  function submitAdd() {
    var s = addField.text.trim()
    if (!s || !engine) return
    engine.add(s)
    addField.text = ""
    leaveAdd(false)
  }

  function tooltipText() {
    if (!engine) return "Torrents"
    if (daemonState !== "running") return "Torrents — daemon " + daemonState
    if (!torrents.length) return "Torrents — nothing added"
    var lines = []
    for (var i = 0; i < Math.min(6, torrents.length); i++) {
      var t = torrents[i]
      lines.push(Model.percent(t.percent) + "  " + t.name + (t.state === "downloading" ? "  " + Model.ARROW_DOWN + " " + Model.speed(t.rateDown) : "  " + Model.stateLabel(t)))
    }
    if (torrents.length > 6) lines.push("… +" + (torrents.length - 6))
    return lines.join("\n")
  }

  implicitWidth: barRow.implicitWidth
  implicitHeight: button.implicitHeight

  Row {
    id: barRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    BarIconButton {
      id: button
      bar: root.bar
      text: root.activeCount > 0 ? Model.DOWNLOAD_ICON : Model.MAGNET_ICON
      foreground: (root.engine && root.engine.errorCount > 0) ? root.badColor
        : root.activeCount > 0 ? root.goodColor : (root.bar ? root.bar.barForeground : Color.foreground)
      active: !!(root.engine && root.engine.lastError)
      tooltipText: root.tooltipText()
      onPressed: function(b) {
        if (b === Qt.RightButton) { if (root.engine) root.engine.rescan(false) }
        else if (b === Qt.MiddleButton) { if (root.engine) { root.engine.checkClipboard(); clipAddTimer.restart() } }
        else root.toggle()
      }

      // One dot per active download, hugging the slot edge below the glyph.
      readonly property int maxDots: 6
      readonly property int dotCount: Math.min(root.activeCount, maxDots)
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
          Rectangle { width: button.dotSize; height: button.dotSize; radius: width / 2; color: root.goodColor }
        }
      }
    }

    // Download speed beside the glyph while anything is downloading.
    Text {
      visible: root.showSpeed && root.activeCount > 0 && root.rateDown > 0 && !button.vertical
      anchors.verticalCenter: parent.verticalCenter
      text: Model.shortSpeed(root.rateDown)
      color: root.goodColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      rightPadding: Style.space(6)
    }
  }

  // Middle-click on the bar icon: add whatever magnet is in the clipboard.
  Timer {
    id: clipAddTimer
    interval: 500
    onTriggered: if (root.engine && root.engine.clipboardCandidate) root.engine.addFromClipboard()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(620))
    readonly property real maxCardHeight: Math.min(panel.availableCardHeight, panel.screenH * 0.9)
    contentHeight: panel.fittedContentHeight(column.implicitHeight, maxCardHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy); else if (dx !== 0) root.filesRow(root.cursor) }
      onReturnRequested: root.activateRow(root.cursor)
      onActivateRequested: root.activateRow(root.cursor)
      onCloseRequested: root.close()
      onDeleteRequested: root.removeRow(root.cursor)
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "a" || t === "/") root.enterAdd()
        else if (t === "p") { if (root.engine) root.engine.addFromClipboard() }
        else if (t === "r") { if (root.engine) root.engine.rescan(false) }
        else if (t === "s") root.pauseRow(root.cursor)
        else if (t === "o") root.folderRow(root.cursor)
        else if (t === "f") root.filesRow(root.cursor)
        else if (t === "q") root.sequentialRow(root.cursor)
        else if (t === "w") root.wantedRow(root.cursor)
        else if (t === "x") root.removeRow(root.cursor)
        else if (t === "X") root.deleteRow(root.cursor)
        else if (t === "O") { if (root.engine) root.engine.pickFile() }
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
            text: Model.MAGNET_ICON + "  Torrents"
            color: root.accentForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            anchors.left: titleText.right
            anchors.leftMargin: Style.space(10)
            anchors.right: titleActions.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: {
              if (!root.engine) return "engine not loaded"
              if (root.daemonState !== "running") return "daemon " + root.daemonState
              var parts = []
              if (root.activeCount) parts.push(root.activeCount + " downloading")
              if (root.engine.seedingCount) parts.push(root.engine.seedingCount + " seeding")
              if (!parts.length) parts.push(root.torrents.length + " torrent" + (root.torrents.length === 1 ? "" : "s"))
              if (root.rateDown > 0 || root.rateUp > 0) parts.push(Model.ARROW_DOWN + " " + Model.speed(root.rateDown) + "  " + Model.ARROW_UP + " " + Model.speed(root.rateUp))
              return parts.join(" · ")
            }
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
              iconText: Model.FILE_ICON
              tooltipText: "Add a .torrent file… (O)"
              foreground: root.accentForeground
              fontFamily: root.fontFamily
              enabled: root.daemonState === "running"
              onClicked: if (root.engine) root.engine.pickFile()
            }
            PanelActionButton {
              iconText: Model.FOLDER_ICON
              tooltipText: "Open the download folder\n" + (root.engine && root.engine.config.downloadDir ? root.engine.config.downloadDir : "")
              foreground: root.accentForeground
              fontFamily: root.fontFamily
              onClicked: if (root.engine) Quickshell.execDetached(["xdg-open", root.engine.config.downloadDir || (Quickshell.env("HOME") + "/Downloads/Torrents")])
            }
            PanelActionButton {
              iconText: Model.REFRESH_ICON
              tooltipText: "Refresh now (r)"
              foreground: root.accentForeground
              fontFamily: root.fontFamily
              onClicked: if (root.engine) root.engine.rescan(true)
            }
            PanelActionButton {
              iconText: Model.POWER_ICON
              tooltipText: root.daemonState === "running" ? "Stop the torrent daemon (stops every transfer and stream)" : "Start the torrent daemon"
              foreground: root.daemonState === "running" ? root.goodColor : root.dimColor
              hoverColor: root.daemonState === "running" ? root.badColor : root.goodColor
              fontFamily: root.fontFamily
              enabled: root.daemonState !== "missing"
              onClicked: if (root.engine) { if (root.daemonState === "running") root.engine.daemonStop(); else root.engine.daemonStart() }
            }
          }
        }

        // ---------- Add row ----------
        Item {
          width: parent.width
          implicitHeight: addField.implicitHeight
          TextField {
            id: addField
            anchors.left: parent.left
            anchors.right: addButton.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "Magnet link, .torrent URL or file path…   (a)"
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            foreground: root.accentForeground
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.daemonState === "running" || root.daemonState === "starting"
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (text !== "") text = ""; else root.leaveAdd(false)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.submitAdd()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.leaveAdd(true)
                event.accepted = true
              }
            }
          }
          Button {
            id: addButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: Model.PLUS_ICON
            text: "Add"
            bordered: true
            foreground: root.accentForeground
            fontFamily: root.fontFamily
            enabled: addField.text.trim() !== "" && root.daemonState === "running"
            onClicked: root.submitAdd()
          }
        }

        // ---------- Clipboard hint ----------
        Rectangle {
          visible: !!(root.engine && root.engine.clipboardCandidate) && root.daemonState === "running"
          width: parent.width
          implicitHeight: visible ? Math.max(clipText.implicitHeight, clipAdd.implicitHeight) + Style.space(8) : 0
          radius: Math.max(3, Style.cornerRadius / 2)
          color: Qt.rgba(root.goodColor.r, root.goodColor.g, root.goodColor.b, 0.10)
          Text {
            id: clipText
            anchors.left: parent.left
            anchors.right: clipAdd.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            text: Model.PASTE_ICON + "  Clipboard: " + (root.engine ? root.engine.clipboardCandidate : "")
            color: root.accentForeground
            elide: Text.ElideMiddle
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Button {
            id: clipAdd
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: "Add it (p)"
            foreground: root.goodColor
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: if (root.engine) root.engine.addFromClipboard()
          }
        }

        // ---------- Notice line ----------
        Text {
          visible: !!(root.engine && root.engine.notice)
          width: parent.width
          text: Model.CHECK_ICON + "  " + (root.engine ? root.engine.notice : "")
          color: root.goodColor
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
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
            readonly property bool isEmpty: modelData.type === "empty"
            readonly property bool isTorrent: modelData.type === "torrent"
            readonly property bool isFile: modelData.type === "file"
            readonly property var t: modelData.t || ({})
            readonly property var f: modelData.f || ({})
            readonly property string busy: (isTorrent || isFile) ? root.busyState(t.id) : ""
            readonly property bool paused: t.state === "paused" || t.state === "done"
            readonly property bool armed: isTorrent && root.confirmDeleteId === t.id
            readonly property bool streaming: !!(root.engine && ((isTorrent && root.engine.isStreaming(t.id)) || (isFile && root.engine.isStreaming(t.id, f.index))))
            width: ListView.view.width
            height: isEmpty ? emptyText.implicitHeight + Style.space(12) : isTorrent ? torrentSurface.implicitHeight : fileSurface.implicitHeight

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

            // ----- Torrent row -----
            CursorSurface {
              id: torrentSurface
              visible: delegateItem.isTorrent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              hasCursor: root.cursorActive && root.cursor === delegateItem.index
              foreground: root.accentForeground
              implicitHeight: visible ? torrentContent.implicitHeight + Style.space(12) : 0

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onEntered: root.cursor = delegateItem.index
                onClicked: root.cursor = delegateItem.index
                onDoubleClicked: root.activateRow(delegateItem.index)
              }

              Item {
                id: torrentContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(4)
                implicitHeight: Math.max(tLabels.implicitHeight, tActions.implicitHeight)

                // Fold arrow: files
                PanelActionButton {
                  id: chevron
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: modelData.expanded ? Model.CHEVRON_DOWN : Model.CHEVRON_RIGHT
                  tooltipText: (modelData.expanded ? "Hide files" : "Show files") + " (f)" + (delegateItem.t.fileCount ? "  · " + delegateItem.t.fileCount + " file" + (delegateItem.t.fileCount === 1 ? "" : "s") : "")
                  foreground: root.dimColor
                  hoverColor: root.accentForeground
                  fontFamily: root.fontFamily
                  enabled: delegateItem.t.fileCount > 0
                  onClicked: root.toggleExpanded(delegateItem.t.id)
                }

                Column {
                  id: tLabels
                  anchors.left: chevron.right
                  anchors.leftMargin: Style.space(4)
                  anchors.right: tActions.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  Item {
                    width: parent.width
                    implicitHeight: nameText.implicitHeight
                    Text {
                      id: nameText
                      anchors.left: parent.left
                      anchors.right: sizeText.left
                      anchors.rightMargin: Style.space(8)
                      text: (delegateItem.streaming ? Model.PLAY_ICON + " " : "") + (delegateItem.t.name || "(fetching name…)")
                      color: delegateItem.t.state === "error" ? root.badColor : root.accentForeground
                      elide: Text.ElideMiddle
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: delegateItem.t.state === "downloading" || delegateItem.streaming
                    }
                    Text {
                      id: sizeText
                      anchors.right: parent.right
                      anchors.baseline: nameText.baseline
                      text: Model.sizeLine(delegateItem.t)
                      color: root.dimColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // Progress bar
                  Rectangle {
                    width: parent.width
                    height: Math.max(3, Style.spaceReal(4))
                    radius: height / 2
                    color: Qt.rgba(root.accentForeground.r, root.accentForeground.g, root.accentForeground.b, 0.15)
                    Rectangle {
                      width: parent.width * Math.max(0, Math.min(1, delegateItem.t.state === "metadata" ? delegateItem.t.metadata : delegateItem.t.percent))
                      height: parent.height
                      radius: height / 2
                      color: delegateItem.t.state === "error" ? root.badColor
                        : delegateItem.paused ? root.dimColor
                        : root.goodColor
                      Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                  }

                  Item {
                    width: parent.width
                    implicitHeight: detailText.implicitHeight
                    Text {
                      id: detailText
                      anchors.left: parent.left
                      anchors.right: pctText.left
                      anchors.rightMargin: Style.space(8)
                      text: delegateItem.busy ? delegateItem.busy + "…" : (delegateItem.armed ? "Press delete again to also erase the downloaded files" : Model.detail(delegateItem.t))
                      color: delegateItem.armed ? root.badColor : delegateItem.t.state === "downloading" ? root.goodColor : delegateItem.t.state === "error" ? root.badColor : root.dimColor
                      elide: Text.ElideRight
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      id: pctText
                      anchors.right: parent.right
                      anchors.baseline: detailText.baseline
                      text: delegateItem.t.state === "metadata" ? "" : Model.percent(delegateItem.t.percent)
                      color: delegateItem.t.percent >= 1 ? root.goodColor : root.dimColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                }

                Row {
                  id: tActions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  PanelActionButton {
                    iconText: Model.PLAY_ICON
                    tooltipText: delegateItem.t.bestMedia >= 0
                      ? "Stream " + (delegateItem.t.files[delegateItem.t.bestMedia] ? delegateItem.t.files[delegateItem.t.bestMedia].base : "") + " (Enter)\nPlays while downloading; seeking jumps the download ahead."
                      : (delegateItem.t.state === "metadata" ? "Waiting for metadata…" : "No video/audio file in this torrent")
                    enabled: delegateItem.t.bestMedia >= 0 && !delegateItem.busy
                    foreground: delegateItem.streaming ? root.goodColor : root.accentForeground
                    hoverColor: root.goodColor
                    fontFamily: root.fontFamily
                    onClicked: root.engine.stream(delegateItem.t.id, delegateItem.t.bestMedia)
                  }
                  PanelActionButton {
                    iconText: Model.SEQ_ICON
                    tooltipText: delegateItem.t.sequential ? "Sequential download on — click for normal (rarest-first) order (q)" : "Download pieces in order, for playback while downloading (q)"
                    foreground: delegateItem.t.sequential ? root.goodColor : root.dimColor
                    hoverColor: root.accentForeground
                    fontFamily: root.fontFamily
                    enabled: !delegateItem.busy
                    onClicked: root.engine.setSequential(delegateItem.t.id, !delegateItem.t.sequential)
                  }
                  PanelActionButton {
                    // A finished torrent "resumes" into seeding, so it gets the upload glyph
                    // instead of a second play triangle next to the stream button.
                    iconText: delegateItem.paused ? (delegateItem.t.percent >= 1 ? Model.SEED_ICON : Model.DOWNLOAD_ICON) : Model.PAUSE_ICON
                    tooltipText: delegateItem.paused ? (delegateItem.t.percent >= 1 ? "Seed (s)" : "Resume (s)") : "Pause (s)"
                    enabled: !delegateItem.busy
                    foreground: root.accentForeground
                    fontFamily: root.fontFamily
                    onClicked: root.engine.toggle(delegateItem.t.id)
                  }
                  PanelActionButton {
                    iconText: Model.FOLDER_ICON
                    tooltipText: "Open folder (o)\n" + (delegateItem.t.downloadDir || "")
                    foreground: root.accentForeground
                    fontFamily: root.fontFamily
                    onClicked: root.engine.openFolder(delegateItem.t.id)
                  }
                  PanelActionButton {
                    iconText: Model.REMOVE_ICON
                    tooltipText: "Remove from the list, keep the files (x)"
                    enabled: !delegateItem.busy
                    foreground: root.accentForeground
                    hoverColor: root.badColor
                    fontFamily: root.fontFamily
                    onClicked: root.engine.remove(delegateItem.t.id, false)
                  }
                  PanelActionButton {
                    iconText: Model.TRASH_ICON
                    tooltipText: delegateItem.armed ? "Click again: remove AND delete the downloaded files" : "Remove and delete the downloaded files (X, twice)"
                    enabled: !delegateItem.busy
                    foreground: delegateItem.armed ? root.badColor : root.accentForeground
                    hoverColor: root.badColor
                    fontFamily: root.fontFamily
                    onClicked: {
                      if (root.confirmDeleteId === delegateItem.t.id) { root.confirmDeleteId = -1; root.engine.remove(delegateItem.t.id, true) }
                      else { root.confirmDeleteId = delegateItem.t.id; confirmTimer.restart() }
                    }
                  }
                }
              }
            }

            // ----- File row -----
            CursorSurface {
              id: fileSurface
              visible: delegateItem.isFile
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              hasCursor: root.cursorActive && root.cursor === delegateItem.index
              foreground: root.accentForeground
              implicitHeight: visible ? fileContent.implicitHeight + Style.space(6) : 0

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onEntered: root.cursor = delegateItem.index
                onClicked: root.cursor = delegateItem.index
                onDoubleClicked: root.activateRow(delegateItem.index)
              }

              Item {
                id: fileContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(34)
                anchors.rightMargin: Style.space(4)
                implicitHeight: Math.max(fileName.implicitHeight, fActions.implicitHeight)

                PanelActionButton {
                  id: wantedBox
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: delegateItem.f.wanted ? Model.CHECKBOX_ON : Model.CHECKBOX_OFF
                  tooltipText: delegateItem.f.wanted ? "Downloading — click to skip this file (w)" : "Skipped — click to download this file (w)"
                  foreground: delegateItem.f.wanted ? root.accentForeground : root.dimColor
                  fontFamily: root.fontFamily
                  size: Style.space(20)
                  onClicked: root.engine.setWanted(delegateItem.t.id, delegateItem.f.index, !delegateItem.f.wanted)
                }
                Text {
                  id: fileIcon
                  anchors.left: wantedBox.right
                  anchors.leftMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  text: delegateItem.f.media ? (Model.isVideo(delegateItem.f.base) ? Model.VIDEO_ICON : Model.MUSIC_ICON) : Model.FILE_ICON
                  color: delegateItem.f.media ? root.accentForeground : root.dimColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  id: fileName
                  anchors.left: fileIcon.right
                  anchors.leftMargin: Style.space(6)
                  anchors.right: fileMeta.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: (delegateItem.streaming ? Model.PLAY_ICON + " " : "") + (delegateItem.f.base || "")
                  color: delegateItem.f.wanted ? root.accentForeground : root.dimColor
                  opacity: delegateItem.f.wanted ? 0.9 : 0.6
                  elide: Text.ElideMiddle
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: delegateItem.streaming
                }
                Text {
                  id: fileMeta
                  anchors.right: fActions.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.size(delegateItem.f.length) + (delegateItem.f.wanted ? "  " + Model.percent(delegateItem.f.percent) : "")
                  color: delegateItem.f.percent >= 1 ? root.goodColor : root.dimColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Row {
                  id: fActions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)
                  PanelActionButton {
                    iconText: Model.PLAY_ICON
                    tooltipText: delegateItem.f.media ? "Stream this file (Enter)" : "Not a media file"
                    enabled: !!delegateItem.f.media && !delegateItem.busy
                    visible: !!delegateItem.f.media
                    foreground: delegateItem.streaming ? root.goodColor : root.accentForeground
                    hoverColor: root.goodColor
                    fontFamily: root.fontFamily
                    size: Style.space(20)
                    fontSize: Style.font.caption
                    onClicked: root.engine.stream(delegateItem.t.id, delegateItem.f.index)
                  }
                }
              }
            }
          }
        }

        // ---------- Key hints ----------
        Text {
          width: parent.width
          text: "↑↓ move · Enter play · s pause/resume · f files · q sequential · w want file · o folder · x remove · X delete files · a add · p paste · O file · Esc close"
          color: root.dimColor
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
