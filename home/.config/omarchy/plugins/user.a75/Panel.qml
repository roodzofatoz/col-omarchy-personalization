import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// VGN A75 widget: bar glyph with the active trigger preset, and a popup for
// presets, actuation / rapid-trigger settings and the firmware hand-off.
// Everything device-side goes through bin/omarchy-a75 via Engine.qml.
Panel {
  id: root
  moduleName: "user.a75"
  ipcTarget: "user.a75"
  manageIpc: false

  readonly property var engine: A75Registry.engine
    || (bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor("user.a75") : null)
  readonly property var status: engine ? engine.status : null
  readonly property bool present: !!(engine && engine.present)
  readonly property bool permissionError: !!(engine && engine.permissionError)
  readonly property bool held: !!(engine && engine.held)
  readonly property bool stalled: !!(engine && engine.stalled)
  // Controls act on the keyboard only when it is reachable and nobody else owns it.
  readonly property bool usable: present && !permissionError && !held && !stalled
  readonly property string lastError: (engine && engine.lastError) ? engine.lastError : ""
  property string adjustedNote: ""
  readonly property string preset: engine ? engine.preset : ""
  // Icon only by default; the preset name is available via the widget setting.
  readonly property bool showPreset: setting("showPresetInBar", false) === true
  readonly property color accentForeground: bar ? bar.foreground : Color.foreground
  // bar is null for a moment on hot reload; binding through here avoids a
  // warning storm from every Text in the popup.
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  onSettingsChanged: pushSettings()
  onEngineChanged: pushSettings()
  Component.onCompleted: pushSettings()
  function pushSettings() {
    if (engine && typeof engine.applySettings === "function") engine.applySettings(settings)
  }

  function refresh() { if (engine) engine.refresh() }
  function nextProfile() {
    if (!engine || engine.profile < 0) return
    engine.run(["profile", String((engine.profile + 1) % 4)], null)
    if (engine) engine.loadProfileState()
  }

  // ---- trigger draft (raw 0.1 mm units) ----------------------------
  property var draft: Model.draftFrom(null)
  property bool dirty: false
  readonly property var profileState: engine ? engine.profileState : null
  readonly property bool busy: !!(engine && engine.busy)
  onProfileStateChanged: if (!dirty) draft = Model.draftFrom(profileState)

  function setDraft(key, value) {
    var next = Object.assign({}, draft)
    next[key] = value
    draft = next
    dirty = true
  }
  // After a successful write, re-sync the sliders from what was actually stored
  // (release may have been lowered to the actuation point) and say so.
  function applied(r, ok) {
    if (!ok) return
    root.dirty = false
    root.draft = Model.draftFrom(root.engine ? root.engine.profileState : null)
    root.adjustedNote = (r && r.adjusted) ? "Some values were adjusted: release cannot exceed actuation and travel is limited to 0.1–4.0 mm." : ""
  }
  function applyAll() {
    if (!engine) return
    adjustedNote = ""
    engine.run(["trigger", "--all"].concat(Model.triggerArgs(draft)), applied)
  }
  function choosePreset(name) {
    if (!engine) return
    engine.run(["preset", name], null)
    dirty = false
    selected = ({})
  }
  function chooseProfile(index) {
    if (!engine) return
    engine.run(["profile", index], null)
    engine.loadProfileState()
    dirty = false
    selected = ({})
  }

  // ---- firmware hand-off (vendor hub via local gRPC helper) ---------
  readonly property string hubBin: Qt.resolvedUrl("bin/omarchy-a75-hub").toString().replace(/^file:\/\//, "")
  property string hubError: ""
  property bool hubBusy: false
  function runHub(action) {
    if (hubProc.running) return
    hubBusy = true
    hubError = ""
    if (engine) engine.stopDepth()      // the hub owns the wire from here on
    hubProc.command = [hubBin, action]
    hubProc.running = true
  }
  function openFirmwareHub() { runHub("open") }
  function stopFirmwareHub() { runHub("stop") }

  // Not detached: build/start failures come back on stderr and are shown in the
  // panel instead of vanishing. The browser and helper live in their own user
  // units, so this process returning does not end them.
  Process {
    id: hubProc
    stdout: StdioCollector { id: hubOut; waitForEnd: true }
    stderr: StdioCollector { id: hubErr; waitForEnd: true }
    onExited: function(code) {
      root.hubBusy = false
      if (code !== 0) {
        root.hubError = (hubErr.text || ("helper exited " + code)).trim().split("\n").slice(-3).join("\n")
        Quickshell.execDetached(["notify-send", "-a", "VGN A75", "Firmware helper failed", root.hubError])
      }
      if (root.engine) root.engine.refresh()
    }
  }

  // ---- per-key selection -------------------------------------------
  property var selected: ({})
  readonly property var selectedSlots: Model.selectedSlots(selected)
  function toggleKey(slot) {
    var next = Object.assign({}, selected)
    if (next[slot]) delete next[slot]; else next[slot] = true
    selected = next
  }
  function applySelected() {
    if (!engine || selectedSlots.length === 0) return
    adjustedNote = ""
    engine.run(["trigger", "--keys", selectedSlots.join(",")].concat(Model.triggerArgs(draft)), applied)
  }

  IpcHandler {
    target: "user.a75"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      if (engine) { engine.loadProfileState(); engine.startDepth() }
      dirty = false
    } else if (engine) {
      engine.stopDepth()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (root.showPreset && root.present && !vertical) ? (Model.presetLabel(root.preset) + " " + Model.KEYBOARD_ICON) : Model.KEYBOARD_ICON
    active: root.permissionError
    opacity: root.present || root.permissionError ? 1 : 0.45
    slotSize: Style.bar.iconSlot * (root.showPreset && root.present && !vertical ? 2.4 : 1)
    tooltipText: "VGN A75 — " + Model.statusLine(root.status)
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) root.nextProfile()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Text {
          text: "VGN A75"
          color: root.accentForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.permissionError ? ("No permission to talk to the keyboard. Run:\n" + Model.INSTALL_LINE + "\nthen replug the keyboard.")
              : root.held ? "The vendor hub is using the keyboard; controls are paused until the helper stops."
              : root.stalled ? "The keyboard's config channel stalled. Unplug and replug it."
              : (root.present ? Model.statusLine(root.status) : "Plug in the A75 over USB.")
          color: Qt.darker(root.accentForeground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          visible: root.lastError !== "" || root.adjustedNote !== ""
          text: root.lastError !== "" ? ("Last command failed: " + root.lastError) : root.adjustedNote
          color: root.lastError !== "" ? (root.bar ? root.bar.urgent : Color.urgent) : Qt.darker(root.accentForeground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Live travel of whichever key is moving (the firmware reports no key id).
        Item {
          width: parent.width
          implicitHeight: Style.space(8)
          visible: root.present
          readonly property var depth: root.engine ? root.engine.depth : null
          readonly property int travel: depth && typeof depth.travel === "number" ? depth.travel : 0
          Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(root.accentForeground.r, root.accentForeground.g, root.accentForeground.b, 0.12) }
          Rectangle {
            height: parent.height; radius: height / 2
            color: root.accentForeground
            width: parent.travel > 0 ? Math.max(height, parent.width * Math.min(1, parent.travel / 40)) : 0
            Behavior on width { NumberAnimation { duration: 50 } }
          }
          Text {
            anchors.right: parent.right; anchors.bottom: parent.top; anchors.bottomMargin: Style.space(2)
            text: parent.travel > 0 ? ("key travel " + Model.mm(parent.travel)) : "press a key to see its travel"
            color: Qt.darker(root.accentForeground, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSectionHeader { text: "PRESET"; foreground: root.accentForeground; fontFamily: root.fontFamily }

        ButtonGroup {
          width: parent.width
          options: Model.PRESET_OPTIONS
          value: root.preset
          foreground: root.accentForeground
          fontFamily: root.fontFamily
          enabled: root.usable && !root.busy
          onChanged: function(v) { root.choosePreset(v) }
        }

        Dropdown {
          width: parent.width
          label: "Profile"
          options: Model.PROFILE_OPTIONS
          value: root.engine && root.engine.profile >= 0 ? String(root.engine.profile) : "0"
          foreground: root.accentForeground
          fontFamily: root.fontFamily
          enabled: root.usable
          onChanged: function(v) { root.chooseProfile(v) }
        }

        PanelSectionHeader { text: "ALL KEYS"; foreground: root.accentForeground; fontFamily: root.fontFamily }

        Repeater {
          model: Model.SLIDERS
          delegate: Column {
            required property var modelData
            width: column.width
            visible: !modelData.rtOnly || root.draft.rt
            spacing: Style.space(4)
            Row {
              width: parent.width
              Text {
                text: modelData.label
                color: root.accentForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                width: parent.width * 0.7
              }
              Text {
                text: Model.mm(root.draft[modelData.key])
                color: root.accentForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignRight
                width: parent.width * 0.3
              }
            }
            PanelSlider {
              width: parent.width
              bar: root.bar
              minimum: modelData.min
              maximum: modelData.max
              step: 1
              integer: true
              value: root.draft[modelData.key]
              onReleased: function(v) { root.setDraft(modelData.key, Math.round(v)) }
            }
          }
        }

        Toggle {
          width: parent.width
          label: "Rapid trigger"
          description: root.draft.rt ? "Re-arms as soon as the key starts to rise" : "Fixed actuation and release points"
          checked: root.draft.rt
          foreground: root.accentForeground
          fontFamily: root.fontFamily
          onClicked: root.setDraft("rt", !root.draft.rt)
        }

        PanelSectionHeader {
          text: root.selectedSlots.length ? ("SELECTED KEYS (" + root.selectedSlots.length + ")") : "KEYS — click to select"
          foreground: root.accentForeground
          fontFamily: root.fontFamily
        }

        Grid {
          id: grid
          columns: 15
          rows: 6
          flow: Grid.TopToBottom
          spacing: Style.space(2)
          width: parent.width
          readonly property real cell: Math.floor((width - spacing * 14) / 15)
          Repeater {
            model: 90
            delegate: Rectangle {
              required property int index
              readonly property var info: Model.keyAt(Math.floor(index / 6), index % 6)
              readonly property bool isSel: !!root.selected[info.slot]
              readonly property bool custom: Model.hasCustom(root.profileState, info.slot)
              width: grid.cell
              height: grid.cell
              radius: 3
              // Empty slots keep their cell so the grid stays aligned; they are just not drawn.
              opacity: info.label === "" ? 0 : (info.key ? 1 : 0.35)
              color: isSel ? root.accentForeground : Qt.rgba(root.accentForeground.r, root.accentForeground.g, root.accentForeground.b, custom ? 0.35 : 0.12)
              Text {
                anchors.centerIn: parent
                text: parent.info.label
                color: parent.isSel ? (root.bar ? root.bar.background : Color.background) : root.accentForeground
                font.family: root.fontFamily
                font.pixelSize: Math.max(7, grid.cell * 0.38)
              }
              MouseArea {
                anchors.fill: parent
                enabled: parent.info.key
                onClicked: root.toggleKey(parent.info.slot)
              }
            }
          }
        }

        Button {
          text: root.selectedSlots.length ? ("Apply to " + root.selectedSlots.length + " key" + (root.selectedSlots.length === 1 ? "" : "s")) : (root.dirty ? "Apply to all keys" : "Applied")
          iconText: Model.KEYBOARD_ICON
          enabled: (root.dirty || root.selectedSlots.length > 0) && root.usable && !root.busy
          foreground: root.accentForeground
          fontFamily: root.fontFamily
          bordered: true
          onClicked: root.selectedSlots.length ? root.applySelected() : root.applyAll()
        }

        PanelSectionHeader { text: "FIRMWARE"; foreground: root.accentForeground; fontFamily: root.fontFamily }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Updates run in VGN's own web hub through a local helper. A firmware update erases on-board settings; keep the page open until the hub reports completion, then re-apply your profile here."
          color: Qt.darker(root.accentForeground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          visible: root.hubError !== ""
          text: root.hubError
          color: root.bar ? root.bar.urgent : Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Row {
          spacing: Style.space(8)
          Button {
            text: root.hubBusy ? "Starting…" : "Open vendor hub"
            iconText: Model.FIRMWARE_ICON
            bordered: true
            enabled: root.present && !root.hubBusy
            foreground: root.accentForeground
            fontFamily: root.fontFamily
            onClicked: root.openFirmwareHub()
          }
          Button {
            text: "Stop helper"
            bordered: true
            enabled: !root.hubBusy
            foreground: root.accentForeground
            fontFamily: root.fontFamily
            onClicked: root.stopFirmwareHub()
          }
        }
      }
    }
  }
}
