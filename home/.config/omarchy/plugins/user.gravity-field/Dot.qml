import QtQuick

// One dot: a single flat circle, no halo or glow.
Rectangle {
  id: dot

  property color core: "white"

  radius: width / 2
  color: core
}
