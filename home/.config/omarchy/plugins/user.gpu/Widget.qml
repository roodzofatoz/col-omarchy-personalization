import QtQuick
import qs.Ui

// Invisible placeholder. The visible UI is the "Gpu" indicator inside the
// hover-revealed indicator block (user.indicators/indicators/Gpu.qml); this
// zero-size widget only exists because a plugin's service (Engine.qml) is
// loaded while the plugin has a bar entry, and it forwards this entry's
// inline settings (checkHours, checkUpstream) to that service.
BarWidget {
  id: root
  moduleName: "user.gpu"
  implicitWidth: 0
  implicitHeight: 0
  visible: false

  // The engine registers itself in GpuRegistry (see GpuRegistry.qml); the bar.shell
  // lookup only works under the trusted first-party bar.
  readonly property var engine: GpuRegistry.engine
    || (bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor("user.gpu") : null)
  onSettingsChanged: pushSettings()
  onEngineChanged: pushSettings()
  Component.onCompleted: pushSettings()
  function pushSettings() {
    if (engine && typeof engine.applySettings === "function") engine.applySettings(settings)
  }
}
