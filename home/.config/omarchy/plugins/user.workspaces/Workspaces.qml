import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // Each monitor owns a block of `blockSize` workspace ids (pinned by the
  // workspace rules in hypr/monitors.lua), but they are shown and clicked as
  // 1-N. So the numbers always act on the monitor you are focused on instead
  // of pulling focus to whichever display owns a global workspace 3.
  readonly property int blockSize: 10

  // Workspace rules keep every workspace inside its monitor's block, so the
  // focused workspace identifies the block without needing to know monitor
  // names. Special workspaces (negative ids) fall back to the first block.
  readonly property int workspaceBase: {
    var current = Hyprland.focusedWorkspace
    if (!current || current.id < 1) return 0
    return Math.floor((current.id - 1) / root.blockSize) * root.blockSize
  }

  function absoluteId(relative) {
    return root.workspaceBase + relative
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // Relative numbers: always 1-5, plus any further workspace that exists in
  // this monitor's block.
  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    var base = root.workspaceBase

    for (var i = 0; i < values.length; i++) {
      var relative = values[i].id - base
      if (relative > 0 && relative <= root.blockSize && ids.indexOf(relative) === -1) ids.push(relative)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(relative) {
    if (!root.bar) return
    var id = root.absoluteId(relative)
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(root.absoluteId(modelData))
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === root.absoluteId(modelData)

        bar: root.bar
        text: focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
