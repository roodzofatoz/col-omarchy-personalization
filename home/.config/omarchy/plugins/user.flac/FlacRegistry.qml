pragma Singleton
import QtQuick

// Process-wide handoff between the engine service (Engine.qml) and the bar
// widgets (Player.qml, one per monitor). Since Omarchy 4.0.3 a widget hosted
// by a third-party bar (user.bar) gets a service-less shell facade, so
// bar.shell.serviceFor("user.flac") returns null; the engine registers itself
// here instead and the widgets bind to it.
QtObject {
  property var engine: null
}
