import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Snipping-tool button: click, drag a region, and it is on the clipboard.
//
// This is a thin front end for omarchy-capture-screenshot. The "copy"
// processing mode pipes grim straight into wl-copy without touching disk,
// which is the Windows Snipping Tool behaviour; the default "slurp" mode
// saves a file as well and offers the editor, which right click keeps.
BarWidget {
  id: root
  moduleName: "user.snip"

  // Off by default: a snip meant for pasting should not litter the
  // screenshots folder. Right click still saves regardless.
  readonly property bool alsoSave: setting("alsoSave", false) === true

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Beside this file, so the plugin keeps working if the directory moves.
  readonly property string snipBin: Qt.resolvedUrl("bin/omarchy-snip").toString().replace(/^file:\/\//, "")

  function snip(save) {
    if (!root.bar) return
    // Own script rather than omarchy-capture-screenshot: that one runs slurp
    // with no colours, which means slurp's default white 25% wash over the
    // screen. This one dims with the theme's darkest background instead.
    // shellQuote lives on Util, not on bar -- the bar README says otherwise,
    // and calling bar.shellQuote threw a TypeError that silently ate the click.
    root.bar.run(Util.shellQuote(root.snipBin) + (save ? " --save" : ""))
  }

  // Only one handler is registered per target, so this fires on a single
  // instance -- which is what we want. Broadcasting would open one slurp per
  // monitor. Bind a key to it with:
  //   o.bind("SUPER + SHIFT + S", "Snip", "omarchy-shell user.snip snip")
  IpcHandler {
    target: "user.snip"

    function snip(): void { root.snip(root.alsoSave) }
    function snipSave(): void { root.snip(true) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: root.alsoSave
      ? "Snip to clipboard and file"
      : "Snip to clipboard · right click also saves"
    onPressed: function(b) {
      root.snip(b === Qt.RightButton ? true : root.alsoSave)
    }
  }
}
