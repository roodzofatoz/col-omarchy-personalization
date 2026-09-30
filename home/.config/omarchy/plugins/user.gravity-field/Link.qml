import QtQuick

// One link between two nearby dots.
//
// Drawn as a thin rotated rectangle rather than a Shape/Canvas path: hundreds
// of these are repositioned every frame, and a plain rotated Rectangle stays on
// the scene-graph fast path where a per-frame Shape rebuild or Canvas repaint
// would not.
Rectangle {
  id: link

  property color tint: "white"

  height: 1
  color: tint
  antialiasing: true
  transformOrigin: Item.Center
}
