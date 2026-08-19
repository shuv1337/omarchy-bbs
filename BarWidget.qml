import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.thoughtlesslabs.omarchy-bbs"
  readonly property string launcherPath: Qt.resolvedUrl("bin/omarchy-bbs").toString().replace("file://", "")
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function command(action) {
    if (!root.bar) return ""
    return root.bar.shellQuote(root.launcherPath) + " " + action
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function launch(action) { if (root.bar) root.bar.run(root.command(action)) }
  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.launcherPath = root.launcherPath
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Timer {
    interval: 300000
    repeat: true
    running: true
    triggeredOnStart: false
    onTriggered: root.launch("status --notify")
  }

  IpcHandler {
    target: "omarchy.bbs"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf489"
    tooltipText: "Tune in to Omarchy BBS"
    active: root.opened
    onPressed: function(b) {
      root.toggle()
    }
  }
}
