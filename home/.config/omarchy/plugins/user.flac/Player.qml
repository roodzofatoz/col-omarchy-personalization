import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// user.flac bar widget: a music glyph in the bar and a keyboard-navigable
// panel with now-playing (with album art), transport, the exclusive-mode
// switch and the library (search, grouping, shuffle). All playback
// state lives in the engine service (Engine.qml); this file only renders it.
// One instance of this exists per monitor, so nothing here may own a process
// or a socket.
Panel {
  id: root
  moduleName: "user.flac"
  // The IPC target is owned by the engine (one handler per target); panel
  // open/close is reached through `omarchy-shell shell toggle user.flac`.
  ipcTarget: ""
  manageIpc: false

  // The engine registers itself in FlacRegistry (see FlacRegistry.qml); the
  // bar.shell lookup only works under the trusted first-party bar.
  readonly property var engine: FlacRegistry.engine
    || (bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor("user.flac") : null)
  readonly property bool engineReady: !!engine
  readonly property bool showTitleInBar: setting("showTitleInBar", false) === true

  readonly property color accentForeground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color goodColor: Color.accent
  // The bar's "urgent" is themed as its active colour (green on Hackerman); a
  // failed bit-perfect check must read as an error, so use the theme urgent.
  readonly property color badColor: Color.urgent

  // "playlist" (the queue mpv is playing) or "library".
  property string tab: "playlist"

  // Library view state. `query` is debounced from the search field.
  property string query: ""
  property string group: "album"
  // Group ordering for Genre/Artist views: "name" (A→Z) or "count" (most tracks first).
  property string groupSort: "name"

  // Album keys the user has opened; albums are collapsed otherwise.
  // `closing`/`opening` hold keys mid-animation (shared by both tabs).
  property var expandedAlbums: ({})
  property var expandedGroups: ({})
  property var closing: ({})
  property var opening: ({})
  readonly property int slideMs: 200
  readonly property var rows: engine ? Model.buildRows(engine.library, { query: query, group: group, sort: groupSort, expanded: expandedAlbums, expandedGroups: expandedGroups, closing: closing, opening: opening }) : []
  readonly property int visibleTracks: Model.allPaths(rows).length
  property var expandedQueue: ({})
  readonly property var queueRows: engine ? Model.queueRows(engine.library, engine.playlist, engine.playlistPos, expandedQueue, closing, opening) : []
  readonly property int queueLength: engine ? engine.playlist.length : 0
  readonly property var activeRows: tab === "playlist" ? queueRows : rows
  readonly property var nextTrack: engine ? engine.nextTrack : null
  readonly property bool narrowed: query !== ""
  readonly property var currentTrack: engine ? engine.track : null
  readonly property string artPath: engine ? engine.artPath : ""
  readonly property var badge: Model.modeBadge(engine, currentTrack)
  readonly property int playingRow: !engine ? -1 : (tab === "playlist" ? Model.queueRowForPos(queueRows, engine.playlistPos) : Model.rowIndexForPath(rows, engine.path))

  // Output chooser shown when exclusive mode is being turned on.
  property bool pickingOutput: false
  property int outputCursor: -1
  function openOutputPicker() {
    if (!engine) return
    engine.listOutputs()
    outputCursor = -1
    pickingOutput = true
  }
  function chooseOutput(index) {
    if (!engine || !engine.outputs.length) return
    if (index < 0) {
      // Enter with nothing highlighted: keep the configured device (or the first).
      index = 0
      for (var i = 0; i < engine.outputs.length; i++) if (engine.outputs[i].alsaDevice === engine.alsaDevice) { index = i; break }
    }
    if (index >= engine.outputs.length) return
    var o = engine.outputs[index]
    pickingOutput = false
    engine.setExclusiveOutput(o.alsaDevice, o.pwDeviceName)
  }

  // Keyboard cursor: -1 = nothing armed (the popup just opened), else a row
  // index in `rows`. Mouse hover moves it too, so one highlight exists.
  property int cursor: -1
  readonly property bool cursorActive: cursor >= 0

  readonly property real openPanelIndicatorWidth: showTitleInBar && !button.vertical ? button.glyphPaintedWidth : 0

  onSettingsChanged: pushSettings()
  onEngineChanged: pushSettings()

  function pushSettings() {
    if (engine && typeof engine.applySettings === "function") engine.applySettings(settings)
  }

  // Flowing-RGB glow for the bar icon while music plays: the hue sweeps the
  // wheel every few seconds; a soft halo of the same colour sits behind it.
  property real hue: 0
  readonly property bool glowing: !!(engine && engine.playing)
  readonly property color glowColor: Qt.hsla(hue, 0.85, 0.62, 1)
  NumberAnimation on hue {
    running: root.glowing
    from: 0; to: 1
    duration: 6000
    loops: Animation.Infinite
  }

  function barText() {
    if (!engine || !engine.path || !showTitleInBar || button.vertical) return Model.DISC_ICON
    var t = engine.title
    if (engine.artist) t = engine.title + " — " + engine.artist
    if (t.length > 40) t = t.substring(0, 39) + "…"
    return Model.DISC_ICON + " " + t
  }

  function tooltipText() {
    if (!engine) return "FLAC player"
    if (!engine.path) return "FLAC player — " + (engine.exclusive ? "exclusive" : "shared")
    return engine.title + (engine.artist ? " — " + engine.artist : "") + "\n" + badge.text
  }

  function badgeColor(state) {
    if (state === "good") return goodColor
    if (state === "bad") return badColor
    if (state === "warn") return Qt.tint(accentForeground, Qt.rgba(badColor.r, badColor.g, badColor.b, 0.5))
    return Qt.darker(accentForeground, 1.4)
  }

  function moveCursor(dy) {
    if (!activeRows.length) return
    if (cursor < 0) cursor = playingRow >= 0 ? playingRow : 0
    else cursor = Math.max(0, Math.min(activeRows.length - 1, cursor + dy))
  }

  function setTab(next) {
    if (tab === next) return
    tab = next
    cursor = -1
  }

  // Enter / click: a track queues its whole album (gapless across the album);
  // album and group rows open or close (play them with ▶ / `a`).
  function activateRow(index) {
    if (!engine || index < 0 || index >= activeRows.length) return
    var row = activeRows[index]
    if (row.type === "queue") engine.playQueueIndex(row.queueIndex)
    else if (row.type === "queueAlbum") { cursor = index; toggleQueueAlbum(row.key, row.expanded) }
    else if (row.type === "track") engine.playAlbum(row.albumIndex, row.trackIndex)
    else if (row.type === "album") { cursor = index; toggleAlbum(row.key) }
    else if (row.type === "group") { cursor = index; toggleGroup(row.key) }
  }

  function toggleGroup(key) {
    var next = Object.assign({}, expandedGroups)
    if (next[key]) { delete next[key]; markClosing(key) }
    else { next[key] = true; markOpening(key) }
    expandedGroups = next
  }

  // `a` / the ▶ on a header: play the highlighted album or group from the top.
  function playRow(index) {
    if (!engine || index < 0 || index >= activeRows.length) return
    var row = activeRows[index]
    if (row.type === "queue" || row.type === "queueAlbum") engine.playQueueIndex(row.queueIndex)
    else if (row.type === "track") engine.playAlbum(row.albumIndex, row.trackIndex)
    else engine.playPaths(row.paths, 0)
  }

  function toggleQueueAlbum(key, expanded) {
    var next = Object.assign({}, expandedQueue)
    next[key] = !expanded
    if (expanded) markClosing(key); else markOpening(key)
    expandedQueue = next
  }

  // `+` / the + on a row: append the highlighted album, group or track to the queue.
  function enqueueRow(index) {
    if (!engine || index < 0 || index >= activeRows.length) return
    var row = activeRows[index]
    if (row.type === "queue" || row.type === "queueAlbum") return
    engine.enqueuePaths(row.type === "track" ? [row.path] : row.paths)
  }

  function removeRow(index) {
    if (!engine || tab !== "playlist" || index < 0 || index >= activeRows.length) return
    var row = activeRows[index]
    if (row.type === "queueAlbum") engine.removeQueueRange(row.queueStart, row.queueEnd)
    else engine.removeQueueIndex(row.queueIndex)
  }

  // The ListView is backed by a ListModel that receives only the changed
  // span of rows (insert/remove below the toggled header), so the view never
  // resets and the header stays exactly where it was clicked. Delegates look
  // their data up in `syncedRows` by index.
  ListModel { id: rowModel }
  property var syncedRows: []
  function syncRows(next) {
    var old = syncedRows
    var n = next.length, m = old.length
    var p = 0
    while (p < n && p < m && old[p].rowKey === next[p].rowKey) p++
    var sfx = 0
    while (sfx < n - p && sfx < m - p && old[m - 1 - sfx].rowKey === next[n - 1 - sfx].rowKey) sfx++
    var removeCount = m - sfx - p
    var insertCount = n - sfx - p
    var fullReplace = p === 0 && sfx === 0
    syncedRows = next
    if (fullReplace) {
      rowModel.clear()
      var all = []
      for (var i = 0; i < n; i++) all.push({ k: next[i].rowKey })
      if (all.length) rowModel.append(all)
    } else {
      if (removeCount > 0) rowModel.remove(p, removeCount)
      for (var j = p; j < n - sfx; j++) rowModel.insert(j, { k: next[j].rowKey })
    }
    if (rowModel.count !== n) {
      console.warn("user.flac: row model drifted (" + rowModel.count + " vs " + n + ", p=" + p + " sfx=" + sfx + " old=" + m + "); rebuilding")
      rowModel.clear()
      var rebuilt = []
      for (var r = 0; r < n; r++) rebuilt.push({ k: next[r].rowKey })
      if (rebuilt.length) rowModel.append(rebuilt)
      return true
    }
    return fullReplace
  }

  function markOpening(key) {
    var o = Object.assign({}, opening); o[key] = true; opening = o
    openingTimer.keys.push(key); openingTimer.restart()
  }
  function markClosing(key) {
    var c = Object.assign({}, closing); c[key] = true; closing = c
    closingTimer.keys.push(key); closingTimer.restart()
  }
  Timer {
    id: openingTimer
    property var keys: []
    interval: root.slideMs + 50
    onTriggered: {
      var o = Object.assign({}, root.opening)
      for (var i = 0; i < keys.length; i++) delete o[keys[i]]
      keys = []
      root.opening = o
    }
  }
  Timer {
    id: closingTimer
    property var keys: []
    interval: root.slideMs + 30
    onTriggered: {
      var c = Object.assign({}, root.closing)
      for (var i = 0; i < keys.length; i++) delete c[keys[i]]
      keys = []
      root.closing = c
    }
  }

  function toggleAlbum(key) {
    var next = Object.assign({}, expandedAlbums)
    if (next[key]) { delete next[key]; markClosing(key) }
    else { next[key] = true; markOpening(key) }
    expandedAlbums = next
  }

  // Shuffle the highlighted header's scope; on a track row (or with no
  // cursor) shuffle everything currently shown.
  function shuffleRow(index) {
    if (!engine) return
    if (tab === "playlist") { engine.toggleShuffle(); return }
    var row = index >= 0 && index < activeRows.length ? activeRows[index] : null
    if (row && row.type !== "track") engine.shufflePaths(row.paths)
    else shuffleVisible()
  }

  function shuffleVisible() {
    if (!engine) return
    engine.shufflePaths(Model.allPaths(rows))
  }

  function cycle(list, current) {
    var keys = list.map(function(x) { return x.key })
    return keys[(keys.indexOf(current) + 1) % keys.length]
  }

  function focusSearch() {
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  function leaveSearch(toList) {
    keyCatcher.forceActiveFocus()
    if (toList && rows.length && cursor < 0) cursor = 0
  }

  onActiveRowsChanged: {
    if (cursor >= activeRows.length) cursor = activeRows.length ? activeRows.length - 1 : -1
    var fullReplace = syncRows(activeRows)
    if (!fullReplace) return
    Qt.callLater(function() {
      var target = cursor >= 0 ? cursor : playingRow
      if (target >= 0 && libraryList.count > target) libraryList.positionViewAtIndex(target, ListView.Contain)
    })
  }

  onOpenedChanged: {
    if (opened) {
      cursor = -1
      if (engine) engine.probeDevice()
      if (engine && !engine.playlist.length) tab = "library"
      Qt.callLater(function() { if (playingRow >= 0) libraryList.positionViewAtIndex(playingRow, ListView.Contain) })
    } else {
      keyCatcher.forceActiveFocus()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Halo behind the disc glyph; only painted while playing. A radial
  // gradient that fades to fully transparent, so there is no visible rim.
  Canvas {
    id: halo
    anchors.centerIn: button
    width: Style.bar.iconSlot * 1.9
    height: width
    visible: root.glowing
    opacity: 0.9
    property color tint: root.glowColor
    onTintChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var r = width / 2
      var g = ctx.createRadialGradient(r, r, 0, r, r, r)
      var c = tint
      g.addColorStop(0.0, Qt.rgba(c.r, c.g, c.b, 0.42))
      g.addColorStop(0.35, Qt.rgba(c.r, c.g, c.b, 0.22))
      g.addColorStop(0.7, Qt.rgba(c.r, c.g, c.b, 0.06))
      g.addColorStop(1.0, Qt.rgba(c.r, c.g, c.b, 0.0))
      ctx.fillStyle = g
      ctx.fillRect(0, 0, width, height)
    }
    SequentialAnimation on scale {
      running: root.glowing
      loops: Animation.Infinite
      NumberAnimation { from: 0.9; to: 1.12; duration: 1600; easing.type: Easing.InOutSine }
      NumberAnimation { from: 1.12; to: 0.9; duration: 1600; easing.type: Easing.InOutSine }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText()
    foreground: root.glowing ? root.glowColor : (root.bar ? root.bar.barForeground : Color.foreground)
    active: !!(root.engine && root.engine.lastError)
    slotSize: root.showTitleInBar && !vertical && root.engine && root.engine.path ? -1 : Style.bar.iconSlot
    fixedWidth: root.showTitleInBar && !vertical && root.engine && root.engine.path ? labelWidth + scaledHorizontalMargin * 2 : -1
    tooltipText: root.tooltipText()
    onPressed: function(b) {
      if (b === Qt.MiddleButton) { if (root.engine) root.engine.playPause() }
      else if (b === Qt.RightButton) { if (root.engine) root.engine.next() }
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      if (!root.engine) return
      if (delta > 0) root.engine.previous()
      else if (delta < 0) root.engine.next()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    // Grow to fit, but never past 90% of the screen; the list below absorbs
    // whatever height is left so nothing spills out of the card.
    readonly property real maxCardHeight: Math.min(panel.availableCardHeight, panel.screenH * 0.9)
    contentHeight: panel.fittedContentHeight(column.implicitHeight, maxCardHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      property bool enterSeen: false
      // While the search field is being typed into, every key belongs to it.
      blocked: searchField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (root.pickingOutput) {
          if (dy !== 0 && root.engine && root.engine.outputs.length)
            root.outputCursor = Math.max(0, Math.min(root.engine.outputs.length - 1, (root.outputCursor < 0 ? 0 : root.outputCursor + dy)))
          return
        }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0 && root.engine) root.engine.seek(dx * 5, false)
      }
      onReturnRequested: {
        enterSeen = true
        if (root.pickingOutput) { root.chooseOutput(root.outputCursor); return }
        root.activateRow(root.cursor)
      }
      onActivateRequested: {
        if (enterSeen) { enterSeen = false; return }
        if (root.engine) root.engine.playPause()
      }
      onCloseRequested: if (root.pickingOutput) root.pickingOutput = false; else root.close()
      onDeleteRequested: root.removeRow(root.cursor)
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "/") { root.setTab("library"); root.focusSearch(); return }
        if (t === "1") { root.setTab("playlist"); return }
        if (t === "2") { root.setTab("library"); return }
        if (t === "+" || t === "=") { root.enqueueRow(root.cursor); return }
        if (t === "g") { root.group = root.cycle(Model.GROUPS, root.group); return }
        if (t === "o") { root.groupSort = root.groupSort === "count" ? "name" : "count"; return }
        if (!root.engine) return
        if (t === "e") { if (root.engine.exclusive) root.engine.setExclusive(false); else if (root.pickingOutput) root.pickingOutput = false; else root.openOutputPicker() }
        else if (t === "r") root.engine.rescan(true)
        else if (t === "n") root.engine.next()
        else if (t === "p") root.engine.previous()
        else if (t === "s") root.engine.stop()
        else if (t === "S") root.shuffleRow(root.cursor)
        else if (t === "a") root.playRow(root.cursor)
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero: album art · now playing ----------
        Item {
          id: heroBlock
          width: parent.width
          implicitHeight: Math.max(artFrame.implicitHeight, heroLabels.implicitHeight)

          // Album art from the library scan (folder cover or the FLAC's own
          // PICTURE block); the note glyph stands in when there is none.
          Item {
            id: artFrame
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Style.space(64)
            implicitHeight: Style.space(64)
            width: implicitWidth
            height: implicitHeight

            Rectangle {
              anchors.fill: parent
              radius: Math.max(4, Style.cornerRadius)
              color: Style.normalFillFor(root.accentForeground, Color.accent)
              visible: !artImage.visible
            }

            Text {
              anchors.centerIn: parent
              visible: !artImage.visible
              text: root.engine && root.engine.path ? (root.engine.paused ? Model.PAUSE_ICON : Model.PLAY_ICON) : Model.MUSIC_ICON
              color: root.accentForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }

            Image {
              id: artImage
              anchors.fill: parent
              visible: root.artPath !== "" && status === Image.Ready
              source: root.artPath !== "" ? Util.fileUrl(root.artPath) : ""
              asynchronous: true
              cache: true
              fillMode: Image.PreserveAspectCrop
              sourceSize.width: Style.space(128)
              sourceSize.height: Style.space(128)
              smooth: true
            }

            Rectangle {
              // Corner mask drawn over the art instead of a shader, so it needs
              // no extra QML modules: a border in the panel background colour.
              anchors.fill: parent
              visible: artImage.visible
              radius: Math.max(4, Style.cornerRadius)
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(root.accentForeground.r, root.accentForeground.g, root.accentForeground.b, 0.25)
            }
          }

          // Up next: a small button in the top-right corner; hovering it
          // previews the following queue entry, clicking skips to it.
          PanelActionButton {
            id: upNext
            anchors.right: parent.right
            anchors.top: parent.top
            visible: !!root.nextTrack
            iconText: Model.QUEUE_ICON
            fontSize: Style.font.icon
            tooltipText: !root.nextTrack ? "" : "Up next"
              + (root.engine && root.engine.playlistCount > 1 ? " (" + (root.engine.playlistPos + 2) + "/" + root.engine.playlistCount + ")" : "")
              + ": " + root.nextTrack.title
              + (root.nextTrack.artist ? " — " + root.nextTrack.artist : "")
              + (root.nextTrack.album ? " · " + root.nextTrack.album : "")
              + "\nClick to skip to it"
            foreground: root.accentForeground
            fontFamily: root.fontFamily
            onClicked: if (root.engine) root.engine.next()
          }

          Column {
            id: heroLabels
            anchors.left: artFrame.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.rightMargin: upNext.visible ? upNext.width + Style.space(8) : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: !root.engine ? "Engine not loaded" : (root.engine.path ? root.engine.title : "Nothing playing")
              color: root.accentForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              visible: text !== ""
              text: root.engine && root.engine.path
                ? [root.engine.artist, root.engine.album].filter(function(x) { return !!x }).join(" — ")
                : (root.engine && root.engine.library ? root.engine.library.count + " tracks · " + root.engine.library.albums.length + " albums" : "")
              color: Qt.darker(root.accentForeground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width
            }

            Row {
              spacing: Style.space(6)
              Rectangle {
                width: Style.space(8); height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.badgeColor(root.badge.state)
              }
              Text {
                text: root.badge.text.toUpperCase()
                color: root.badgeColor(root.badge.state)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
              }
            }
          }
        }

        Text {
          id: errorText
          visible: !!(root.engine && root.engine.lastError)
          width: parent.width
          text: root.engine ? root.engine.lastError : ""
          color: root.badColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---------- Transport ----------
        Column {
          id: transportBlock
          width: parent.width
          spacing: Style.space(4)

          Item {
            width: parent.width
            implicitHeight: seekSlider.implicitHeight

            PanelSlider {
              id: seekSlider
              anchors.left: parent.left
              anchors.right: parent.right
              bar: root.bar
              minimum: 0
              maximum: root.engine && root.engine.duration > 0 ? root.engine.duration : 1
              step: 1
              value: root.engine ? root.engine.timePos : 0
              enabled: !!(root.engine && root.engine.path)
              opacity: enabled ? 1 : 0.4
              onReleased: function(v) { if (root.engine) root.engine.seek(v, true) }
            }
          }

          Item {
            width: parent.width
            implicitHeight: transportRow.implicitHeight

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.engine ? Model.formatTime(root.engine.timePos) : "0:00"
              color: Qt.darker(root.accentForeground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              id: transportRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(4)

              TransportButton {
                iconText: Model.SHUFFLE_ICON
                tooltipText: root.engine && root.engine.shuffleOn ? "Shuffle on — click to restore order (S)" : "Shuffle the queue (S)"
                selected: !!(root.engine && root.engine.shuffleOn)
                onClicked: root.engine.toggleShuffle()
              }
              TransportButton { iconText: Model.PREV_ICON; tooltipText: "Previous (p)"; onClicked: root.engine.previous() }
              TransportButton {
                iconText: root.engine && root.engine.playing ? Model.PAUSE_ICON : Model.PLAY_ICON
                tooltipText: "Play / pause (Space)"
                onClicked: root.engine.playPause()
              }
              TransportButton { iconText: Model.NEXT_ICON; tooltipText: "Next (n)"; onClicked: root.engine.next() }
              TransportButton { iconText: Model.STOP_ICON; tooltipText: "Stop — pause and rewind to the start (s)"; onClicked: root.engine.stop() }
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: (root.engine && root.engine.playlistCount > 1 ? (root.engine.playlistPos + 1) + "/" + root.engine.playlistCount + "  " : "")
                + (root.engine ? Model.formatTime(root.engine.duration) : "0:00")
              color: Qt.darker(root.accentForeground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        PanelSeparator { id: sep1; foreground: root.accentForeground }

        // ---------- Output mode ----------
        Toggle {
          id: modeToggle
          width: parent.width
          label: "Exclusive mode (bit-perfect)"
          description: root.engine && root.engine.exclusive
            ? "mpv owns the DAC via ALSA hw:; PipeWire releases it while playing. Volume is set on the DAC."
            : "Playing through PipeWire; other apps share the output (graph rate applies)."
          checked: root.engine ? root.engine.exclusive : false
          foreground: root.accentForeground
          fontFamily: root.fontFamily
          onClicked: {
            if (!root.engine) return
            if (root.engine.exclusive) { root.pickingOutput = false; root.engine.setExclusive(false) }
            else if (root.pickingOutput) root.pickingOutput = false
            else root.openOutputPicker()
          }
        }

        // ---------- Output chooser (exclusive mode) ----------
        Column {
          id: outputPicker
          visible: root.pickingOutput
          width: parent.width
          spacing: Style.space(4)

          PanelSectionHeader {
            text: root.engine && root.engine.outputsLoading ? "CHOOSE OUTPUT — SCANNING…" : "CHOOSE OUTPUT FOR EXCLUSIVE MODE"
            foreground: root.accentForeground
            fontFamily: root.fontFamily
          }

          Text {
            visible: !!(root.engine && !root.engine.outputsLoading && root.engine.outputs.length === 0)
            width: parent.width
            text: "No hardware playback devices found."
            color: Qt.darker(root.accentForeground, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.engine ? root.engine.outputs : []
            delegate: CursorSurface {
              id: outRow
              required property var modelData
              required property int index
              readonly property bool isCurrent: !!(root.engine && root.engine.alsaDevice === modelData.alsaDevice)
              width: parent.width
              implicitHeight: outCol.implicitHeight + Style.space(10)
              hasCursor: root.outputCursor === index
              current: isCurrent
              foreground: root.accentForeground

              Column {
                id: outCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(1)
                Text {
                  width: parent.width
                  text: modelData.label + (outRow.isCurrent ? "  ·  current" : "")
                  color: root.accentForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: outRow.isCurrent
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: modelData.description
                  color: Qt.darker(root.accentForeground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.outputCursor = index
                onClicked: root.chooseOutput(index)
              }
            }
          }

          Row {
            spacing: Style.space(6)
            Chip { text: "Cancel"; onClicked: root.pickingOutput = false }
            ChipLabel { text: "↑↓ · Enter · Esc" }
          }
        }

        PanelSeparator { id: sep2; foreground: root.accentForeground }

        // ---------- Tabs: Playlist | Library, with per-tab actions ----------
        Item {
          id: tabsBlock
          width: parent.width
          implicitHeight: Math.max(tabRow.implicitHeight, libActions.implicitHeight)

          Row {
            id: tabRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Chip {
              text: "Playlist" + (root.queueLength ? " · " + root.queueLength : "")
              selected: root.tab === "playlist"
              tooltipText: "The queue mpv is playing (1)"
              onClicked: root.setTab("playlist")
            }
            Chip {
              text: root.engine && root.engine.scanning ? "Library · scanning…" : "Library" + (root.narrowed ? " · " + root.visibleTracks : "")
              selected: root.tab === "library"
              tooltipText: "Browse and add to the playlist (2)"
              onClicked: root.setTab("library")
            }
          }

          Row {
            id: libActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            PanelActionButton {
              visible: root.tab === "playlist"
              iconText: Model.CLEAR_ICON
              tooltipText: "Clear the playlist (stops playback)"
              foreground: root.accentForeground
              hoverColor: root.badColor
              fontFamily: root.fontFamily
              enabled: root.queueLength > 0
              onClicked: if (root.engine) root.engine.clearQueue()
            }
            PanelActionButton {
              visible: root.tab === "library" && root.group !== "album"
              iconText: root.groupSort === "count" ? Model.SORT_COUNT_ICON : Model.SORT_AZ_ICON
              tooltipText: root.groupSort === "count"
                ? "Sorted by track count (most first) — click for A→Z (o)"
                : "Sorted A→Z — click for most tracks first (o)"
              foreground: root.accentForeground
              fontFamily: root.fontFamily
              onClicked: root.groupSort = root.groupSort === "count" ? "name" : "count"
            }
            PanelActionButton {
              visible: root.tab === "library"
              iconText: Model.SHUFFLE_ICON
              tooltipText: root.narrowed ? "Shuffle the tracks shown (S)" : "Shuffle all songs (S)"
              foreground: root.accentForeground
              fontFamily: root.fontFamily
              enabled: root.visibleTracks > 0
              onClicked: root.shuffleVisible()
            }
            PanelActionButton {
              visible: root.tab === "library"
              iconText: Model.REFRESH_ICON
              tooltipText: "Rescan library (r)"
              foreground: root.accentForeground
              fontFamily: root.fontFamily
              onClicked: if (root.engine) root.engine.rescan(true)
            }
            PanelActionButton {
              visible: root.tab === "library"
              iconText: Model.FOLDER_ICON
              tooltipText: "Select library folder…\n" + (root.engine ? root.engine.libraryDir : "")
              foreground: root.accentForeground
              fontFamily: root.fontFamily
              enabled: !(root.engine && root.engine.pickingLibrary)
              onClicked: if (root.engine) root.engine.selectLibraryDir()
            }
          }
        }

        // ---------- Search (library tab) ----------
        TextField {
          id: searchField
          visible: root.tab === "library"
          width: parent.width
          placeholderText: "Search title, artist, album, genre, year…   ( / )"
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          foreground: root.accentForeground
          horizontalPadding: Style.spacing.controlGap
          verticalPadding: Style.spacing.controlPaddingY
          onTextChanged: queryDebounce.restart()
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              if (text !== "") { text = ""; root.query = "" }
              root.leaveSearch(false)
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.leaveSearch(true)
              event.accepted = true
            }
          }
        }

        Timer {
          id: queryDebounce
          interval: 120
          onTriggered: root.query = searchField.text
        }

        // ---------- Grouping chips (library tab) ----------
        Flow {
          id: chipsBlock
          visible: root.tab === "library"
          width: parent.width
          spacing: Style.space(6)

          ChipLabel { text: "GROUP BY" }
          Repeater {
            model: Model.GROUPS
            Chip {
              required property var modelData
              text: modelData.label
              selected: root.group === modelData.key
              onClicked: root.group = modelData.key
            }
          }
        }

        Text {
          id: emptyText
          visible: root.activeRows.length === 0
          width: parent.width
          text: root.tab === "playlist"
            ? "The playlist is empty. Open the Library tab and press + on an album, or Enter to play one."
            : root.engine && root.engine.scanning
            ? "Scanning…"
            : (root.narrowed
              ? "No tracks match."
              : (root.engine && root.engine.library && root.engine.library.missing
                ? "Library folder not available: " + root.engine.libraryDir + "\nIs the drive mounted? Press rescan (r) or pick another folder."
                : "No FLAC files found in " + (root.engine ? root.engine.libraryDir : "the library") + ". Drop albums there and press rescan."))
          color: Qt.darker(root.accentForeground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // ---------- Library list ----------
        ListView {
          id: libraryList
          visible: root.activeRows.length > 0
          width: parent.width
          // Everything in the column except this list, plus the column gaps.
          readonly property real siblingsHeight: {
            var items = [heroBlock, errorText, transportBlock, sep1, modeToggle, outputPicker, sep2, tabsBlock, searchField, chipsBlock, emptyText, hintText]
            var total = 0, shown = 0
            for (var i = 0; i < items.length; i++) {
              if (!items[i].visible) continue
              total += items[i].implicitHeight
              shown++
            }
            return total + column.spacing * shown
          }
          readonly property real budget: panel.maxCardHeight - panel.verticalContentInset - siblingsHeight
          height: Math.min(contentHeight, Math.max(Style.space(160), budget))
          spacing: Style.space(2)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          // Delegates carry per-row animation state, so no reuse.
          reuseItems: false

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          model: rowModel
          currentIndex: root.cursor
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Item {
            id: delegateItem
            required property int index
            // Row data comes from the synced array, not the ListModel (which
            // only carries keys), so nested arrays like `paths` stay intact.
            readonly property bool hasData: index >= 0 && index < root.syncedRows.length && !!root.syncedRows[index]
            readonly property var modelData: hasData ? root.syncedRows[index] : ({ type: "track", title: "", subtitle: "", meta: "", paths: [], path: "" })
            visible: hasData
            readonly property bool isTrack: modelData.type === "track"
            readonly property bool isGroup: modelData.type === "group"
            readonly property bool isAlbum: modelData.type === "album"
            readonly property bool isQueue: modelData.type === "queue"
            readonly property bool isQueueAlbum: modelData.type === "queueAlbum"
            readonly property bool isHeader: isAlbum || isQueueAlbum
            readonly property int indent: isQueue ? 24 : isQueueAlbum ? 6 : isGroup ? 6
              : (isAlbum ? (root.group === "album" ? 6 : 18) : (root.group === "album" ? 24 : 36))
            width: ListView.view.width
            // Slide: track rows grow from 0 when their album opens and shrink
            // back to 0 while it closes; headers are never animated.
            readonly property bool slides: isTrack || isQueue || isAlbum
            // `appeared` flips a frame after creation so opening rows animate
            // from 0; the binding stays intact so a later `closing` flag can
            // animate them back down.
            property bool appeared: !(slides && modelData.opening)
            readonly property real reveal: slides && (modelData.closing || !appeared) ? 0 : 1
            property real shown: reveal
            Behavior on shown { NumberAnimation { duration: root.slideMs; easing.type: Easing.InOutQuad } }
            Component.onCompleted: if (!appeared) Qt.callLater(function() { appeared = true })
            height: hasData ? rowSurface.implicitHeight * shown : 0
            opacity: shown
            clip: true

            CursorSurface {
              id: rowSurface
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              hasCursor: root.cursorActive && root.cursor === delegateItem.index
              current: (delegateItem.isTrack || delegateItem.isQueue || (delegateItem.isQueueAlbum && !modelData.expanded)) && root.playingRow === delegateItem.index
              foreground: root.accentForeground
              implicitHeight: rowContent.implicitHeight + Style.space(delegateItem.isTrack || delegateItem.isQueue ? 8 : (delegateItem.isHeader ? 6 : 10))

              Item {
                id: rowContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(delegateItem.indent)
                anchors.rightMargin: Style.space(6)
                implicitHeight: Math.max(rowTitle.implicitHeight + (rowSub.visible ? rowSub.implicitHeight : 0), rowMeta.implicitHeight, rowShuffle.visible ? rowShuffle.implicitHeight : 0, rowArt.visible ? rowArt.height : 0)

                // Chevron + cover thumbnail on album rows.
                Text {
                  id: rowChevron
                  visible: delegateItem.isHeader || delegateItem.isGroup
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: visible ? Style.space(16) : 0
                  text: modelData.expanded ? Model.CHEVRON_DOWN_ICON : Model.CHEVRON_RIGHT_ICON
                  color: Qt.darker(root.accentForeground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                }

                Item {
                  id: rowArt
                  visible: delegateItem.isHeader   // groups have no cover
                  anchors.left: rowChevron.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: visible ? Style.space(38) : 0
                  height: visible ? Style.space(38) : 0

                  Rectangle {
                    anchors.fill: parent
                    radius: Math.max(3, Style.cornerRadius / 2)
                    color: Style.normalFillFor(root.accentForeground, Color.accent)
                    visible: !rowArtImage.visible
                    Text {
                      anchors.centerIn: parent
                      text: Model.ALBUM_ICON
                      color: Qt.darker(root.accentForeground, 1.3)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.icon
                    }
                  }
                  Image {
                    id: rowArtImage
                    anchors.fill: parent
                    visible: rowArt.visible && modelData.art !== "" && status === Image.Ready
                    source: rowArt.visible && modelData.art !== "" ? Util.fileUrl(modelData.art) : ""
                    asynchronous: true
                    cache: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Style.space(76)
                    sourceSize.height: Style.space(76)
                    smooth: true
                  }
                }

                Text {
                  id: rowNumber
                  visible: delegateItem.isTrack || delegateItem.isQueue
                  anchors.left: rowArt.right
                  anchors.leftMargin: delegateItem.isHeader ? Style.space(10) : 0
                  anchors.top: rowTitle.top
                  width: visible ? Style.space(delegateItem.isQueue ? 34 : 22) : 0
                  text: modelData.number ? modelData.number + "." : ""
                  color: Qt.darker(root.accentForeground, 1.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  id: rowTitle
                  anchors.left: rowNumber.right
                  anchors.leftMargin: delegateItem.isHeader || delegateItem.isGroup ? Style.space(10) : 0
                  anchors.right: rowMeta.left
                  anchors.rightMargin: Style.space(8)
                  anchors.top: parent.top
                  text: modelData.title
                  color: root.accentForeground
                  font.family: root.fontFamily
                  font.pixelSize: delegateItem.isGroup ? Style.font.subtitle : Style.font.body
                  font.bold: !delegateItem.isTrack || root.playingRow === delegateItem.index
                  font.letterSpacing: delegateItem.isGroup ? 0.6 : 0
                  elide: Text.ElideRight
                }

                Text {
                  id: rowSub
                  visible: modelData.subtitle !== ""
                  anchors.left: rowNumber.right
                  anchors.leftMargin: delegateItem.isHeader ? Style.space(10) : 0
                  anchors.right: rowMeta.left
                  anchors.top: rowTitle.bottom
                  text: modelData.subtitle
                  color: Qt.darker(root.accentForeground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Text {
                  id: rowMeta
                  anchors.right: rowAdd.visible ? rowAdd.left : (rowQueuePlay.visible ? rowQueuePlay.left : (rowRemove.visible ? rowRemove.left : parent.right))
                  anchors.rightMargin: rowAdd.visible || rowRemove.visible ? Style.space(4) : 0
                  anchors.verticalCenter: parent.verticalCenter
                  text: delegateItem.isTrack || delegateItem.isQueue ? modelData.meta + "  " + Model.formatTime(modelData.duration) : modelData.meta
                  color: Qt.darker(root.accentForeground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                // Header rows get their own play and shuffle: this album /
                // this genre / this artist, without touching the rest.
                PanelActionButton {
                  id: rowAdd
                  visible: !delegateItem.isTrack && !delegateItem.isQueue && !delegateItem.isQueueAlbum
                  anchors.right: rowPlay.left
                  anchors.rightMargin: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Model.PLUS_ICON
                  fontSize: Style.font.iconSmall
                  tooltipText: "Add " + (delegateItem.isGroup ? "this group" : "this album") + " to the playlist (+)"
                  foreground: root.accentForeground
                  fontFamily: root.fontFamily
                  onClicked: root.enqueueRow(delegateItem.index)
                }

                PanelActionButton {
                  id: rowRemove
                  visible: delegateItem.isQueue || delegateItem.isQueueAlbum
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Model.REMOVE_ICON
                  fontSize: Style.font.iconSmall
                  tooltipText: (delegateItem.isQueueAlbum ? "Remove this album from the playlist" : "Remove from the playlist") + " (x)"
                  foreground: root.accentForeground
                  hoverColor: root.badColor
                  fontFamily: root.fontFamily
                  onClicked: root.removeRow(delegateItem.index)
                }

                PanelActionButton {
                  id: rowQueuePlay
                  visible: delegateItem.isQueueAlbum
                  anchors.right: rowRemove.left
                  anchors.rightMargin: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Model.PLAY_ICON
                  fontSize: Style.font.iconSmall
                  tooltipText: "Play this album from the top (a)"
                  foreground: root.accentForeground
                  fontFamily: root.fontFamily
                  onClicked: root.playRow(delegateItem.index)
                }

                PanelActionButton {
                  id: rowPlay
                  visible: !delegateItem.isTrack && !delegateItem.isQueue && !delegateItem.isQueueAlbum
                  anchors.right: rowShuffle.left
                  anchors.rightMargin: Style.space(2)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Model.PLAY_ICON
                  fontSize: Style.font.iconSmall
                  tooltipText: "Play " + (delegateItem.isGroup ? "this group" : "this album") + " (a)"
                  foreground: root.accentForeground
                  fontFamily: root.fontFamily
                  onClicked: root.playRow(delegateItem.index)
                }

                PanelActionButton {
                  id: rowShuffle
                  visible: !delegateItem.isTrack && !delegateItem.isQueue && !delegateItem.isQueueAlbum
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Model.SHUFFLE_ICON
                  fontSize: Style.font.iconSmall
                  tooltipText: "Shuffle " + (delegateItem.isGroup ? "this group" : "this album")
                  foreground: root.accentForeground
                  fontFamily: root.fontFamily
                  onClicked: root.shuffleRow(delegateItem.index)
                }
              }

              MouseArea {
                anchors.fill: parent
                anchors.rightMargin: rowShuffle.visible ? rowShuffle.width + rowPlay.width + rowAdd.width + Style.space(14)
                  : (rowRemove.visible ? rowRemove.width + (rowQueuePlay.visible ? rowQueuePlay.width + Style.space(2) : 0) + Style.space(10) : 0)
                hoverEnabled: true
                onEntered: root.cursor = delegateItem.index
                onClicked: root.activateRow(delegateItem.index)
              }
            }
          }
        }

        Text {
          id: hintText
          width: parent.width
          text: root.tab === "playlist"
            ? "↑↓ move · ⏎ play track / open album · a play album · x remove · S shuffle toggle · 2 library"
            : "↑↓ move · ⏎ open group / album · play track · + add to playlist · a play · S shuffle · / search · g group"
          color: Qt.darker(root.accentForeground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  // One size and one fixed box for every transport glyph so they share a
  // baseline regardless of how tall the individual icons are drawn.
  component TransportButton: Button {
    foreground: root.accentForeground
    fontFamily: root.fontFamily
    iconSize: Style.font.iconLarge
    horizontalPadding: Style.space(10)
    verticalPadding: Style.space(4)
    implicitWidth: Style.space(40)
    implicitHeight: Style.space(32)
    enabled: root.engineReady
    opacity: enabled ? 1 : 0.4
  }

  component Chip: Button {
    foreground: root.accentForeground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    horizontalPadding: Style.space(8)
    verticalPadding: Style.space(2)
    bordered: true
  }

  component ChipLabel: Text {
    color: Qt.darker(root.accentForeground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    height: Style.spacing.controlHeight * 0.8
    verticalAlignment: Text.AlignVCenter
    leftPadding: Style.space(2)
    rightPadding: Style.space(4)
  }
}
