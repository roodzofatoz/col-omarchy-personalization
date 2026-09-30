pragma Singleton
import QtQuick

// Handoff between the engine service and the bar widget. Under the user.bar
// clone bar.shell.serviceFor() returns null (Omarchy 4.0.3), so the engine
// registers itself here and the panel binds to it.
QtObject {
  property var engine: null
}
