import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.thoughtlesslabs.omarchy-bbs"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string launcherPath: ""
  property string screen: "loading"
  property string handle: ""
  property string errorMessage: ""
  property var currentThread: ({})
  property string pendingAction: ""
  property string pendingInput: ""
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string panelFont: bar ? bar.fontFamily : Style.font.family

  function open() { root.controller.show(); refreshIdentity() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function run(action, input) {
    if (bridge.running || launcherPath === "") return
    errorMessage = ""
    pendingAction = action
    pendingInput = input || ""
    bridge.command = [launcherPath, action]
    bridge.running = true
  }
  function refreshIdentity() { screen = "loading"; run("identity", "") }
  function refreshThreads() { screen = "loading"; run("threads", "") }
  function openThread(id) { screen = "loading"; run("thread", JSON.stringify({thread_id: id})) }
  function parseResult(text) {
    var result
    try { result = JSON.parse(String(text || "{}")) }
    catch (e) { errorMessage = "The receiver returned an unreadable signal."; return }
    if (!result.ok) { errorMessage = result.error || "The request failed."; if (screen === "loading") screen = handle ? "threads" : "onboarding"; return }
    if (pendingAction === "identity") {
      if (result.registered) { handle = result.handle; refreshThreads() }
      else { handleField.text = result.suggested_handle; screen = "onboarding" }
    } else if (pendingAction === "register") {
      handle = result.handle; refreshThreads()
    } else if (pendingAction === "threads") {
      threadModel.clear()
      var rows = result.threads || []
      for (var i = 0; i < rows.length; ++i) threadModel.append(rows[i])
      handle = result.handle || handle; screen = "threads"
    } else if (pendingAction === "thread") {
      currentThread = result.thread; screen = "thread"
    } else if (pendingAction === "create") {
      subjectField.text = ""; composeBody.text = ""; openThread(result.thread_id)
    } else if (pendingAction === "reply") {
      replyBody.text = ""; openThread(currentThread.id)
    }
  }

  ListModel { id: threadModel }

  Process {
    id: bridge
    stdinEnabled: true
    onStarted: { if (root.pendingInput !== "") write(root.pendingInput + "\n") }
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseResult(text) }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) { if (code !== 0 && root.errorMessage === "") root.errorMessage = "The BBS receiver could not complete the request." }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(650)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: { if (root.screen === "thread" || root.screen === "compose") root.refreshThreads(); else root.close() }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if ((text === "r" || text === "R") && root.screen === "threads") root.refreshThreads()
        else if ((text === "n" || text === "N") && root.screen === "threads") root.screen = "compose"
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: content.implicitHeight
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

        Column {
          id: content
          width: scroller.width - (scroller.contentHeight > scroller.height ? Style.space(8) : 0)
          spacing: Style.space(9)

        PanelHero {
          width: parent.width
          title: "OMARCHY // BBS"
          meta: root.handle ? "@" + root.handle : "LOCAL FREQUENCY"
          detail: root.screen === "onboarding" ? "TUNE IN" : "ENCRYPTED AT REST"
          foreground: root.foreground
          fontFamily: root.panelFont
          iconComponent: Component {
            Item {
              implicitWidth: Style.space(42); implicitHeight: Style.space(42)
              Text { anchors.centerIn: parent; text: "\uf489"; color: root.accent; font.family: root.panelFont; font.pixelSize: Style.font.display }
              Rectangle { width: Style.space(6); height: width; radius: width / 2; color: root.accent; anchors.right: parent.right; anchors.bottom: parent.bottom }
            }
          }
        }

        PanelSeparator { width: parent.width }

        Text {
          visible: root.errorMessage !== ""
          width: parent.width
          text: "! " + root.errorMessage
          color: Color.error
          font.family: root.panelFont
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.screen === "loading"
          width: parent.width; text: "SCANNING FREQUENCY…"; color: root.foreground
          font.family: root.panelFont; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignHCenter
        }

        Column {
          visible: root.screen === "onboarding"
          width: parent.width; spacing: Style.space(10)
          PanelSectionHeader { text: "CHOOSE YOUR CALL SIGN"; foreground: root.foreground; fontFamily: root.panelFont }
          Text { width: parent.width; text: "Your hostname is suggested. Change it now if you want—this public name identifies your transmissions."; color: Qt.darker(root.foreground, 1.35); font.family: root.panelFont; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }
          TextField { id: handleField; width: parent.width; foreground: root.foreground; placeholderText: "hostname"; maximumLength: 32; onAccepted: joinButton.clicked() }
          Button { id: joinButton; width: parent.width; text: bridge.running ? "Tuning…" : "Join frequency"; iconText: "\uf1eb"; leftAlign: true; bordered: true; focusable: true; foreground: root.foreground; enabled: !bridge.running; onClicked: root.run("register", JSON.stringify({handle: handleField.text})) }
          Text { width: parent.width; text: "Registration requires the installed Omarchy client. Your device credential stays on this machine."; color: Qt.darker(root.foreground, 1.5); font.family: root.panelFont; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
        }

        Column {
          visible: root.screen === "threads"
          width: parent.width; spacing: Style.space(7)
          Row { width: parent.width; spacing: Style.space(7)
            Button { width: (parent.width - parent.spacing) * .62; text: "New transmission"; iconText: "\uf4ad"; leftAlign: true; bordered: true; foreground: root.foreground; onClicked: root.screen = "compose" }
            Button { width: (parent.width - parent.spacing) * .38; text: "Refresh"; iconText: "\uf021"; leftAlign: true; bordered: true; foreground: root.foreground; onClicked: root.refreshThreads() }
          }
          Text { visible: threadModel.count === 0; width: parent.width; text: "NO TRANSMISSIONS YET — YOU HAVE THE CHANNEL."; color: Qt.darker(root.foreground, 1.35); font.family: root.panelFont; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }
          Repeater {
            model: threadModel
            delegate: Button {
              required property int id; required property string title; required property string handle; required property string created_at; required property int replies
              width: parent.width; text: title + "\n@" + handle + "  ·  " + replies + " repl.  ·  " + created_at; iconText: "\uf075"; leftAlign: true; bordered: true; foreground: root.foreground; onClicked: root.openThread(id)
            }
          }
          Text { width: parent.width; text: "N  NEW    R  REFRESH    ESC  CLOSE"; color: Qt.darker(root.foreground, 1.5); font.family: root.panelFont; font.pixelSize: Style.font.caption }
        }

        Column {
          visible: root.screen === "compose"
          width: parent.width; spacing: Style.space(8)
          PanelSectionHeader { text: "NEW TRANSMISSION"; foreground: root.foreground; fontFamily: root.panelFont }
          TextField { id: subjectField; width: parent.width; foreground: root.foreground; placeholderText: "Subject"; maximumLength: 120 }
          Controls.TextArea { id: composeBody; width: parent.width; height: Style.space(150); placeholderText: "Write something worth reading."; wrapMode: TextEdit.Wrap; color: root.foreground; font.family: root.panelFont; font.pixelSize: Style.font.body; background: Rectangle { color: Color.background; border.color: Qt.darker(root.foreground, 1.8); radius: Style.cornerRadius } }
          Row { spacing: Style.space(7)
            Button { text: "Transmit"; iconText: "\uf1d8"; bordered: true; foreground: root.foreground; enabled: !bridge.running; onClicked: root.run("create", JSON.stringify({title: subjectField.text, body: composeBody.text})) }
            Button { text: "Cancel"; bordered: true; foreground: root.foreground; onClicked: root.refreshThreads() }
          }
        }

        Column {
          visible: root.screen === "thread"
          width: parent.width; spacing: Style.space(8)
          Button { text: "Back to frequency"; iconText: "\uf060"; bordered: true; foreground: root.foreground; onClicked: root.refreshThreads() }
          Text { width: parent.width; text: root.currentThread.title || ""; color: root.accent; font.family: root.panelFont; font.pixelSize: Style.font.heading; font.bold: true; wrapMode: Text.WordWrap }
          Text { width: parent.width; text: "@" + (root.currentThread.handle || "") + "  ·  " + (root.currentThread.created_at || ""); color: Qt.darker(root.foreground, 1.4); font.family: root.panelFont; font.pixelSize: Style.font.caption }
          Text { width: parent.width; text: root.currentThread.body || ""; color: root.foreground; font.family: root.panelFont; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
          Repeater {
            model: root.currentThread.replies || []
            delegate: Rectangle {
              required property var modelData
              width: parent.width
              implicitHeight: replyColumn.implicitHeight + Style.space(14)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05)
              radius: Style.cornerRadius
              Column {
                id: replyColumn
                anchors.fill: parent
                anchors.margins: Style.space(7)
                spacing: Style.space(4)
                Text {
                  width: parent.width
                  text: "@" + modelData.handle + "  ·  " + modelData.created_at
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.panelFont
                  font.pixelSize: Style.font.caption
                }
                Text {
                  width: parent.width
                  text: modelData.body
                  color: root.foreground
                  font.family: root.panelFont
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
              }
            }
          }
          Controls.TextArea { id: replyBody; width: parent.width; height: Style.space(90); placeholderText: "Reply on this frequency"; wrapMode: TextEdit.Wrap; color: root.foreground; font.family: root.panelFont; font.pixelSize: Style.font.body; background: Rectangle { color: Color.background; border.color: Qt.darker(root.foreground, 1.8); radius: Style.cornerRadius } }
          Button { text: "Reply"; iconText: "\uf1d8"; bordered: true; foreground: root.foreground; enabled: !bridge.running; onClicked: root.run("reply", JSON.stringify({thread_id: root.currentThread.id, body: replyBody.text})) }
        }
      }
      }
    }
  }
}
