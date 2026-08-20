import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.thoughtlesslabs.omarchy-bbs"
  readonly property string launcherPath: Qt.resolvedUrl("bin/omarchy-bbs").toString().replace("file://", "")
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  property int unreadCount: 0
  property int mentionCount: 0
  property bool updateAvailable: false
  property string latestVersion: ""

  function command(action) {
    if (!root.bar) return ""
    return Util.shellQuote(root.launcherPath) + " " + action
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function launch(action) { if (root.bar) root.bar.run(root.command(action)) }
  function refreshStatus() {
    if (!statusProcess.running && root.launcherPath !== "") {
      statusProcess.command = [root.launcherPath, "status", "--notify"]
      statusProcess.running = true
    }
  }
  function installUpdate() {
    if (root.bar) root.bar.run("omarchy plugin update io.github.thoughtlesslabs.omarchy-bbs --yes")
  }
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
    interval: 60000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Process {
    id: statusProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var result = JSON.parse(String(text || "{}"))
          if (result.ok) {
            root.unreadCount = Number(result.unread || 0)
            root.mentionCount = Number(result.mentions || 0)
            root.updateAvailable = result.update_available === true
            root.latestVersion = String(result.latest_version || "")
          }
        } catch (e) {}
      }
    }
  }

  IpcHandler {
    target: "omarchy.bbs"
    function state(): string { return JSON.stringify({loaded: !!panelLoader.item, opened: root.opened, hasBar: !!root.bar, launcher: root.launcherPath, panel: panelLoader.item ? panelLoader.item.diagnostic() : null}) }
    function open(): void { root.open() }
    function openThread(threadId: int): void { if (panelLoader.item) panelLoader.item.openToThread(threadId) }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf086"
    tooltipText: root.mentionCount > 0 ? "Omarchy BBS · " + root.mentionCount + " mention" + (root.mentionCount === 1 ? "" : "s") : (root.unreadCount > 0 ? "Omarchy BBS · new board activity" : "Open Omarchy BBS")
    active: root.opened || root.mentionCount > 0
    onPressed: function(b) {
      root.toggle()
    }
  }

  Rectangle {
    visible: root.mentionCount > 0
    width: Style.space(6)
    height: width
    radius: width / 2
    color: Color.accent
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: Style.space(2)
    anchors.topMargin: Style.space(2)
  }
}
